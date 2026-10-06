namespace Singularity.Apps.Publish {

    public class Hyphenator {
        public string language;
        public string source = "";
        public int left_min = 2;
        public int right_min = 3;
        public int min_word = 5;
        private Gee.HashMap<string, string> patterns = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> exceptions = new Gee.HashMap<string, string> ();
        private int max_len = 0;
        private static Gee.HashMap<string, Hyphenator?>? cache = null;
        public static string[]? search_dirs = null;

        public Hyphenator (string language) {
            this.language = language;
        }

        public int pattern_count () {
            return patterns.size;
        }

        public void add_pattern (string pattern) {
            string p = pattern.strip ();
            if (p == "" || p.contains ("/") || p.has_prefix ("%")) return;
            var letters = new StringBuilder ();
            var digits = new StringBuilder ();
            bool pending = false;
            unichar c;
            int i = 0;
            while (p.get_next_char (ref i, out c)) {
                if (c.isdigit ()) {
                    digits.append_c ((char) ('0' + c.digit_value ()));
                    pending = true;
                } else {
                    if (!pending) digits.append_c ('0');
                    letters.append_unichar (c.tolower ());
                    pending = false;
                }
            }
            if (!pending) digits.append_c ('0');
            string key = letters.str;
            patterns[key] = digits.str;
            max_len = int.max (max_len, key.char_count ());
        }

        public void add_exception (string word) {
            string w = word.strip ();
            if (w == "") return;
            exceptions[w.replace ("-", "").down ()] = w.down ();
        }

        public void load_text (string text, bool libhyphen) {
            string[] lines = text.split ("\n");
            int start = 0;
            if (libhyphen && lines.length > 0) start = 1;
            for (int i = start; i < lines.length; i++) {
                string l = lines[i].strip ();
                if (l == "" || l.has_prefix ("%") || l.has_prefix ("#")) continue;
                if (l.has_prefix ("LEFTHYPHENMIN")) {
                    left_min = int.parse (l.substring (13).strip ()).clamp (1, 6);
                    continue;
                }
                if (l.has_prefix ("RIGHTHYPHENMIN")) {
                    right_min = int.parse (l.substring (14).strip ()).clamp (1, 6);
                    continue;
                }
                if (l.has_prefix ("NEXTLEVEL") || l.has_prefix ("NOHYPHEN") || l.has_prefix ("COMPOUND")) continue;
                foreach (string part in l.split_set (" \t")) {
                    if (part == "") continue;
                    if (!libhyphen && part.contains ("-") && !part.contains (".")) add_exception (part);
                    else add_pattern (part);
                }
            }
        }

        private static string? tex_group (string text, string command) {
            int start = text.index_of (command);
            if (start < 0) return null;
            int open = text.index_of ("{", start);
            if (open < 0) return null;
            int close = text.index_of ("}", open);
            if (close < 0) return null;
            return text.substring (open + 1, close - open - 1);
        }

        public void load_tex (string text) {
            var sb = new StringBuilder ();
            foreach (string line in text.split ("\n")) {
                int c = line.index_of ("%");
                sb.append (c >= 0 ? line.substring (0, c) : line);
                sb.append_c ('\n');
            }
            string clean = sb.str;
            string? pats = tex_group (clean, "\\patterns");
            if (pats != null) foreach (string part in pats.split_set (" \t\n")) if (part != "") add_pattern (part);
            string? exc = tex_group (clean, "\\hyphenation");
            if (exc != null) foreach (string part in exc.split_set (" \t\n")) if (part != "") add_exception (part);
        }

        public static string[] dirs () {
            if (search_dirs != null) return search_dirs;
            var l = new Gee.ArrayList<string> ();
            l.add (Path.build_filename (Environment.get_user_data_dir (), "singularity", "hyphen"));
            foreach (string d in Environment.get_system_data_dirs ()) {
                l.add (Path.build_filename (d, "hyphen"));
                l.add (Path.build_filename (d, "singularity", "hyphen"));
                l.add (Path.build_filename (d, "myspell", "dicts"));
                l.add (Path.build_filename (d, "texlive", "texmf-dist", "tex", "generic", "hyph-utf8", "patterns", "txt"));
                l.add (Path.build_filename (d, "texmf", "tex", "generic", "hyph-utf8", "patterns", "txt"));
            }
            return l.to_array ();
        }

        private static string[] candidates (string lang) {
            string l = lang.replace ("-", "_");
            string base_lang = l.split ("_")[0].down ();
            var names = new Gee.ArrayList<string> ();
            names.add ("hyph_%s.dic".printf (l));
            if (base_lang == "en") {
                names.add ("hyph_en_US.dic");
                names.add ("hyph_en_GB.dic");
            }
            names.add ("hyph_%s_%s.dic".printf (base_lang, base_lang.up ()));
            names.add ("hyph_%s.dic".printf (base_lang));
            if (base_lang == "en") names.add ("hyph-en-us.pat.txt");
            names.add ("hyph-%s.pat.txt".printf (l.down ().replace ("_", "-")));
            names.add ("hyph-%s.pat.txt".printf (base_lang));
            if (base_lang == "en") names.add ("hyphen.tex");
            return names.to_array ();
        }

        public static string? dictionary_path (string lang) {
            foreach (string d in dirs ()) {
                foreach (string n in candidates (lang)) {
                    string p = Path.build_filename (d, n);
                    if (FileUtils.test (p, FileTest.IS_REGULAR)) return p;
                }
            }
            return null;
        }

        public static Hyphenator? for_language (string lang) {
            if (cache == null) cache = new Gee.HashMap<string, Hyphenator?> ();
            string key = lang == "" ? "en" : lang;
            if (cache.has_key (key)) return cache[key];
            Hyphenator? h = null;
            string? path = dictionary_path (key);
            if (path != null) {
                try {
                    h = load_file (key, path);
                } catch (Error e) {
                    h = null;
                }
            }
            cache[key] = h;
            return h;
        }

        public static void reset_cache () {
            cache = null;
        }

        public static Hyphenator load_file (string lang, string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            var h = new Hyphenator (lang);
            h.source = path;
            bool libhyphen = path.has_suffix (".dic");
            if (libhyphen) {
                string first = text.split ("\n")[0].strip ().up ();
                if (first != "UTF-8" && first != "UTF8") {
                    try {
                        text = convert (text, -1, "UTF-8", first == "" ? "ISO-8859-1" : first);
                    } catch (ConvertError e) {
                        text = convert (text, -1, "UTF-8", "ISO-8859-1");
                    }
                }
            } else if (!text.validate ()) {
                throw new FormatError.INVALID (_("The hyphenation patterns are not valid UTF-8."));
            }
            if (path.has_suffix (".tex")) {
                h.load_tex (text);
                return h;
            }
            h.load_text (text, libhyphen);
            if (!libhyphen) {
                string exc = path.replace (".pat.txt", ".hyp.txt");
                if (exc != path && FileUtils.test (exc, FileTest.IS_REGULAR)) {
                    string et;
                    FileUtils.get_contents (exc, out et);
                    foreach (string w in et.split_set (" \n\t")) h.add_exception (w);
                }
            }
            return h;
        }

        public int[] points (string word) {
            return points_with (word, left_min, right_min, min_word);
        }

        public static int[] explicit_points (string hyphenated) {
            int[] result = {};
            int idx = 0;
            unichar c;
            int i = 0;
            while (hyphenated.get_next_char (ref i, out c)) {
                if (c == '-' || c == '~') result += idx;
                else idx++;
            }
            return result;
        }

        public int[] points_with (string word, int lmin, int rmin, int minw) {
            int n = word.char_count ();
            int[] result = {};
            if (n < minw || n < lmin + rmin) return result;
            string low = word.down ();
            if (exceptions.has_key (low)) {
                string e = exceptions[low];
                int idx = 0;
                unichar c;
                int i = 0;
                while (e.get_next_char (ref i, out c)) {
                    if (c == '-') result += idx;
                    else idx++;
                }
                return result;
            }
            string dotted = "." + low + ".";
            unichar[] chars = {};
            int bi = 0;
            unichar uc;
            while (dotted.get_next_char (ref bi, out uc)) chars += uc;
            int len = chars.length;
            int[] levels = new int[len + 1];
            for (int s = 0; s < len; s++) {
                var sb = new StringBuilder ();
                for (int e = s; e < len && e - s < max_len; e++) {
                    sb.append_unichar (chars[e]);
                    string? v = patterns[sb.str];
                    if (v == null) continue;
                    for (int k = 0; k < v.length; k++) {
                        int d = v[k] - '0';
                        if (d > levels[s + k]) levels[s + k] = d;
                    }
                }
            }
            for (int i = lmin; i <= n - rmin; i++) {
                if (levels[i + 1] % 2 == 1) result += i;
            }
            return result;
        }

        public string hyphenate (string word, string mark = "-") {
            int[] pts = points (word);
            if (pts.length == 0) return word;
            var sb = new StringBuilder ();
            int idx = 0;
            int pi = 0;
            unichar c;
            int i = 0;
            while (word.get_next_char (ref i, out c)) {
                if (pi < pts.length && pts[pi] == idx) {
                    sb.append (mark);
                    pi++;
                }
                sb.append_unichar (c);
                idx++;
            }
            return sb.str;
        }

        public static string describe (string lang) {
            var h = for_language (lang);
            if (h == null) return _("No hyphenation dictionary for \"%s\" is installed. Words break only at hyphens and discretionary hyphens.").printf (lang);
            return _("Hyphenation uses %s (%d patterns).").printf (Path.get_basename (h.source), h.pattern_count ());
        }
    }
}
