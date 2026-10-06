namespace Singularity.Apps.Publish {

    public enum NestedUnit {
        CHARACTERS,
        WORDS,
        SENTENCES,
        TABS,
        CHARACTER,
        DIGITS,
        LETTERS;

        public static string[] labels () {
            return { _("Characters"), _("Words"), _("Sentences"), _("Tabs"), _("Specific Character"), _("Digits"), _("Letters") };
        }
    }

    public class NestedStyle {
        public string cstyle;
        public bool through = true;
        public int count = 1;
        public NestedUnit unit = NestedUnit.WORDS;
        public string character = ":";

        public NestedStyle (string cstyle) {
            this.cstyle = cstyle;
        }

        public NestedStyle clone () {
            var n = new NestedStyle (cstyle);
            n.through = through;
            n.count = count;
            n.unit = unit;
            n.character = character;
            return n;
        }

        private bool matches (unichar c) {
            switch (unit) {
                case NestedUnit.CHARACTERS: return true;
                case NestedUnit.WORDS: return c == ' ' || c == '\t' || c == 0x00A0 || c == 0x2028;
                case NestedUnit.SENTENCES: return c == '.' || c == '!' || c == '?';
                case NestedUnit.TABS: return c == '\t';
                case NestedUnit.CHARACTER: return character != "" && character.get_char (0) == c;
                case NestedUnit.DIGITS: return c.isdigit ();
                case NestedUnit.LETTERS: return c.isalpha ();
                default: return false;
            }
        }

        public int extent (string text, int from) {
            int seen = 0;
            int i = from;
            unichar c;
            int prev = i;
            bool in_word = false;
            while (text.get_next_char (ref i, out c)) {
                if (unit == NestedUnit.WORDS) {
                    bool sep = matches (c);
                    if (!sep) in_word = true;
                    else if (in_word) {
                        seen++;
                        in_word = false;
                        if (seen >= count) return through ? i : prev;
                    }
                } else if (matches (c)) {
                    seen++;
                    if (seen >= count) return through ? i : prev;
                }
                prev = i;
            }
            return text.length;
        }

        public void write (XmlOut x) {
            x.start ("nested").a ("cstyle", cstyle).ai ("through", through ? 1 : 0).ai ("count", count).ai ("unit", (int) unit).a ("char", character).end ();
        }

        public static NestedStyle read (Xml.Node* n) {
            var s = new NestedStyle (XmlIn.attr (n, "cstyle") ?? "");
            s.through = XmlIn.int_attr (n, "through", 1) == 1;
            s.count = int.max (1, XmlIn.int_attr (n, "count", 1));
            s.unit = (NestedUnit) XmlIn.int_attr (n, "unit", 1).clamp (0, 6);
            s.character = XmlIn.attr (n, "char") ?? ":";
            return s;
        }
    }

    public class GrepStyle {
        public string cstyle;
        public string pattern;

        public GrepStyle (string cstyle, string pattern) {
            this.cstyle = cstyle;
            this.pattern = pattern;
        }

        public GrepStyle clone () {
            return new GrepStyle (cstyle, pattern);
        }

        public void write (XmlOut x) {
            x.start ("grep-style").a ("cstyle", cstyle).a ("pattern", pattern).end ();
        }

        public static GrepStyle read (Xml.Node* n) {
            return new GrepStyle (XmlIn.attr (n, "cstyle") ?? "", XmlIn.attr (n, "pattern") ?? "");
        }
    }

    public class StyleOverlay {
        public int start;
        public int end;
        public string cstyle;

        public StyleOverlay (int start, int end, string cstyle) {
            this.start = start;
            this.end = end;
            this.cstyle = cstyle;
        }
    }

    public class StyleRules {
        private static Gee.HashMap<string, Regex?>? cache = null;

        public static Regex? compile (string pattern) {
            if (cache == null) cache = new Gee.HashMap<string, Regex?> ();
            if (cache.has_key (pattern)) return cache[pattern];
            Regex? r = null;
            try {
                r = new Regex (pattern, RegexCompileFlags.OPTIMIZE);
            } catch (RegexError e) {
                r = null;
            }
            cache[pattern] = r;
            return r;
        }

        public static Gee.List<NestedStyle> nested_for (Publication pub, string style) {
            var chain = pub.styles.para_chain (style);
            for (int i = chain.size - 1; i >= 0; i--) if (chain[i].nested.size > 0) return chain[i].nested;
            return new Gee.ArrayList<NestedStyle> ();
        }

        public static Gee.List<GrepStyle> grep_for (Publication pub, string style) {
            var chain = pub.styles.para_chain (style);
            for (int i = chain.size - 1; i >= 0; i--) if (chain[i].grep.size > 0) return chain[i].grep;
            return new Gee.ArrayList<GrepStyle> ();
        }

        public static Gee.ArrayList<StyleOverlay> overlays (Publication pub, string style, string text, int from) {
            var list = new Gee.ArrayList<StyleOverlay> ();
            int pos = from;
            foreach (var n in nested_for (pub, style)) {
                if (pos >= text.length) break;
                int end = n.extent (text, pos);
                if (end > pos && n.cstyle != "") list.add (new StyleOverlay (pos, end, n.cstyle));
                pos = int.max (pos, end);
            }
            foreach (var g in grep_for (pub, style)) {
                if (g.pattern == "" || g.cstyle == "") continue;
                var re = compile (g.pattern);
                if (re == null) continue;
                MatchInfo mi;
                if (!re.match (text.substring (from), 0, out mi)) continue;
                int guard = 0;
                while (mi.matches () && guard++ < 10000) {
                    int a, b;
                    if (mi.fetch_pos (0, out a, out b) && b > a) list.add (new StyleOverlay (from + a, from + b, g.cstyle));
                    try {
                        if (!mi.next ()) break;
                    } catch (RegexError e) {
                        break;
                    }
                }
            }
            return list;
        }
    }
}
