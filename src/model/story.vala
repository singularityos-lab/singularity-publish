namespace Singularity.Apps.Publish {

    public const unichar OBJ_CHAR = 0xFFFC;
    public const string OBJ_STR = "\xef\xbf\xbc";

    public struct TextPos {
        public int para;
        public int offset;

        public TextPos (int para, int offset) {
            this.para = para;
            this.offset = offset;
        }

        public int compare (TextPos o) {
            if (para != o.para) return para < o.para ? -1 : 1;
            if (offset != o.offset) return offset < o.offset ? -1 : 1;
            return 0;
        }

        public bool equals (TextPos o) {
            return para == o.para && offset == o.offset;
        }
    }

    public class Run {
        public string text = "";
        public string cstyle = "";
        public CharFormat fmt = new CharFormat ();
        public string field = "";
        public Item? anchor = null;
        public AnchorSpec? anchor_spec = null;
        public Story? note = null;
        public string condition = "";

        public Run (string text = "") {
            this.text = text;
        }

        public Run.field_run (string field) {
            this.text = OBJ_STR;
            this.field = field;
        }

        public Run.anchored (Item item, AnchorSpec spec) {
            this.text = OBJ_STR;
            this.field = AnchorSpec.FIELD;
            this.anchor = item;
            this.anchor_spec = spec;
        }

        public int length () {
            return text.char_count ();
        }

        public Run clone () {
            var r = new Run (text);
            r.cstyle = cstyle;
            r.fmt = fmt.clone ();
            r.field = field;
            if (anchor != null) r.anchor = anchor.clone ();
            if (anchor_spec != null) r.anchor_spec = anchor_spec.clone ();
            if (note != null) r.note = note.clone ();
            r.condition = condition;
            return r;
        }

        public Run clone_format (string new_text) {
            var r = new Run (new_text);
            r.cstyle = cstyle;
            r.fmt = fmt.clone ();
            r.condition = condition;
            return r;
        }

        public bool same_format (Run o) {
            return cstyle == o.cstyle && condition == o.condition && fmt.equals (o.fmt);
        }
    }

    public class Paragraph {
        public string style = StyleSheet.BASIC;
        public string anchor = "";
        public ParaFormat fmt = new ParaFormat ();
        public Gee.ArrayList<Run> runs = new Gee.ArrayList<Run> ();

        public Paragraph (string style = StyleSheet.BASIC) {
            this.style = style;
        }

        public Paragraph.with_text (string text, string style = StyleSheet.BASIC) {
            this.style = style;
            runs.add (new Run (text));
        }

        public string text () {
            var sb = new StringBuilder ();
            foreach (var r in runs) sb.append (r.text);
            return sb.str;
        }

        public int length () {
            int n = 0;
            foreach (var r in runs) n += r.length ();
            return n;
        }

        public Paragraph clone () {
            var p = new Paragraph (style);
            p.fmt = fmt.clone ();
            p.anchor = anchor;
            foreach (var r in runs) p.runs.add (r.clone ());
            return p;
        }

        public Paragraph clone_empty () {
            var p = new Paragraph (style);
            p.fmt = fmt.clone ();
            return p;
        }

        public void normalize () {
            var list = new Gee.ArrayList<Run> ();
            Run? template = runs.size > 0 ? runs[0] : null;
            foreach (var r in runs) {
                if (r.text == "") {
                    template = r;
                    continue;
                }
                if (list.size > 0) {
                    var last = list[list.size - 1];
                    if (last.field == "" && r.field == "" && last.same_format (r)) {
                        last.text += r.text;
                        continue;
                    }
                }
                list.add (r);
            }
            if (list.size == 0) list.add (template != null ? template.clone_format ("") : new Run (""));
            runs = list;
        }

        public int split_at (int offset) {
            int pos = 0;
            for (int i = 0; i < runs.size; i++) {
                var r = runs[i];
                int len = r.length ();
                if (offset == pos) return i;
                if (offset < pos + len) {
                    if (r.field != "") return i;
                    int local = offset - pos;
                    int bi = r.text.index_of_nth_char (local);
                    var tail = r.clone_format (r.text.substring (bi));
                    r.text = r.text.substring (0, bi);
                    runs.insert (i + 1, tail);
                    return i + 1;
                }
                pos += len;
            }
            return runs.size;
        }

        public Run format_run_at (int offset) {
            int pos = 0;
            Run? last = null;
            foreach (var r in runs) {
                int len = r.length ();
                if (offset > pos && offset <= pos + len && r.field == "") return r;
                if (r.field == "") last = r;
                if (offset == 0 && pos == 0 && r.field == "") return r;
                pos += len;
            }
            if (last != null) return last;
            return runs.size > 0 ? runs[0] : new Run ("");
        }

        public string field_at (int offset) {
            int pos = 0;
            foreach (var r in runs) {
                int len = r.length ();
                if (offset >= pos && offset < pos + len) return r.field;
                pos += len;
            }
            return "";
        }
    }

    public delegate void RunFunc (Run r);
    public delegate void ParaFunc (Paragraph p);

    public class Story {
        public int id;
        public Gee.ArrayList<Paragraph> paras = new Gee.ArrayList<Paragraph> ();
        public Gee.ArrayList<int> frames = new Gee.ArrayList<int> ();
        public string link_path = "";
        public string link_stamp = "";
        public int source_story = 0;

        public Story (int id) {
            this.id = id;
            paras.add (new Paragraph.with_text (""));
        }

        public Story.from_text (int id, string text, string style = StyleSheet.BASIC) {
            this.id = id;
            foreach (string line in text.split ("\n")) paras.add (new Paragraph.with_text (line, style));
        }

        public Story clone () {
            var s = new Story (id);
            s.paras.clear ();
            foreach (var p in paras) s.paras.add (p.clone ());
            s.frames.add_all (frames);
            s.link_path = link_path;
            s.link_stamp = link_stamp;
            s.source_story = source_story;
            return s;
        }

        public bool is_empty () {
            return paras.size == 0 || (paras.size == 1 && paras[0].length () == 0);
        }

        public int char_count () {
            int n = 0;
            foreach (var p in paras) n += p.length () + 1;
            return int.max (0, n - 1);
        }

        public string plain_text () {
            var sb = new StringBuilder ();
            for (int i = 0; i < paras.size; i++) {
                if (i > 0) sb.append ("\n");
                sb.append (paras[i].text ());
            }
            return sb.str;
        }

        public TextPos end_pos () {
            int last = paras.size - 1;
            return TextPos (last, paras[last].length ());
        }

        public TextPos clamp (TextPos p) {
            int para = p.para.clamp (0, paras.size - 1);
            return TextPos (para, p.offset.clamp (0, paras[para].length ()));
        }

        public int linear (TextPos p) {
            int n = 0;
            for (int i = 0; i < p.para && i < paras.size; i++) n += paras[i].length () + 1;
            return n + p.offset;
        }

        public TextPos from_linear (int n) {
            for (int i = 0; i < paras.size; i++) {
                int len = paras[i].length ();
                if (n <= len) return TextPos (i, int.max (0, n));
                n -= len + 1;
            }
            return end_pos ();
        }

        public Run format_at (TextPos p) {
            var c = clamp (p);
            return paras[c.para].format_run_at (c.offset);
        }

        public TextPos insert_text (TextPos at, string text, Run? template = null) {
            var pos = clamp (at);
            var fmt = template ?? format_at (pos);
            string[] lines = text.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n");
            for (int li = 0; li < lines.length; li++) {
                if (li > 0) pos = split_paragraph (pos);
                string chunk = lines[li];
                if (chunk == "") continue;
                var para = paras[pos.para];
                int idx = para.split_at (pos.offset);
                var run = fmt.clone_format (chunk);
                para.runs.insert (idx, run);
                para.normalize ();
                pos = TextPos (pos.para, pos.offset + chunk.char_count ());
            }
            return pos;
        }

        public TextPos insert_field (TextPos at, string field) {
            var pos = clamp (at);
            var fmt = format_at (pos);
            var para = paras[pos.para];
            int idx = para.split_at (pos.offset);
            var run = fmt.clone_format (OBJ_STR);
            run.field = field;
            para.runs.insert (idx, run);
            para.normalize ();
            return TextPos (pos.para, pos.offset + 1);
        }

        public TextPos split_paragraph (TextPos at) {
            var pos = clamp (at);
            var para = paras[pos.para];
            int idx = para.split_at (pos.offset);
            var np = para.clone_empty ();
            Run template = para.format_run_at (pos.offset);
            for (int i = idx; i < para.runs.size; i++) np.runs.add (para.runs[i]);
            while (para.runs.size > idx) para.runs.remove_at (para.runs.size - 1);
            if (np.runs.size == 0) np.runs.add (template.clone_format (""));
            para.normalize ();
            np.normalize ();
            paras.insert (pos.para + 1, np);
            return TextPos (pos.para + 1, 0);
        }

        public void delete_range (TextPos a, TextPos b) {
            var s = clamp (a);
            var e = clamp (b);
            if (s.compare (e) > 0) {
                var t = s;
                s = e;
                e = t;
            }
            if (s.equals (e)) return;
            if (s.para == e.para) {
                var p = paras[s.para];
                Run keep = p.format_run_at (s.offset);
                int i1 = p.split_at (s.offset);
                int i2 = p.split_at (e.offset);
                for (int i = i2 - 1; i >= i1; i--) p.runs.remove_at (i);
                if (p.runs.size == 0) p.runs.add (keep.clone_format (""));
                p.normalize ();
                return;
            }
            var first = paras[s.para];
            var last = paras[e.para];
            Run keep = first.format_run_at (s.offset);
            int fi = first.split_at (s.offset);
            while (first.runs.size > fi) first.runs.remove_at (first.runs.size - 1);
            int li = last.split_at (e.offset);
            for (int i = li; i < last.runs.size; i++) first.runs.add (last.runs[i]);
            for (int i = e.para; i > s.para; i--) paras.remove_at (i);
            if (first.runs.size == 0) first.runs.add (keep.clone_format (""));
            first.normalize ();
        }

        public void apply_chars (TextPos a, TextPos b, RunFunc f) {
            var s = clamp (a);
            var e = clamp (b);
            if (s.compare (e) > 0) {
                var t = s;
                s = e;
                e = t;
            }
            for (int pi = s.para; pi <= e.para; pi++) {
                var p = paras[pi];
                int from = pi == s.para ? s.offset : 0;
                int to = pi == e.para ? e.offset : p.length ();
                if (from == to) {
                    if (p.length () == 0) foreach (var r in p.runs) f (r);
                    continue;
                }
                int i1 = p.split_at (from);
                int i2 = p.split_at (to);
                for (int i = i1; i < i2; i++) f (p.runs[i]);
                p.normalize ();
            }
        }

        public void apply_paras (TextPos a, TextPos b, ParaFunc f) {
            int p1 = int.min (a.para, b.para).clamp (0, paras.size - 1);
            int p2 = int.max (a.para, b.para).clamp (0, paras.size - 1);
            for (int i = p1; i <= p2; i++) f (paras[i]);
        }

        public Story copy_range (TextPos a, TextPos b) {
            var s = clamp (a);
            var e = clamp (b);
            if (s.compare (e) > 0) {
                var t = s;
                s = e;
                e = t;
            }
            var frag = clone ();
            frag.delete_range (TextPos (e.para, e.offset), frag.end_pos ());
            frag.delete_range (TextPos (0, 0), s);
            return frag;
        }

        public TextPos insert_story (TextPos at, Story frag) {
            var pos = clamp (at);
            if (frag.paras.size == 0) return pos;
            var tail_pos = split_paragraph (pos);
            var head = paras[pos.para];
            var tail = paras[tail_pos.para];
            foreach (var r in frag.paras[0].runs) head.runs.add (r.clone ());
            head.normalize ();
            if (frag.paras.size == 1) {
                int end_off = head.length ();
                foreach (var r in tail.runs) head.runs.add (r);
                head.normalize ();
                paras.remove_at (tail_pos.para);
                return TextPos (pos.para, end_off);
            }
            int insert_at = pos.para + 1;
            for (int i = 1; i < frag.paras.size - 1; i++) paras.insert (insert_at++, frag.paras[i].clone ());
            var last = frag.paras[frag.paras.size - 1].clone ();
            int end_off = last.length ();
            foreach (var r in tail.runs) last.runs.add (r);
            last.normalize ();
            paras[insert_at] = last;
            return TextPos (insert_at, end_off);
        }

        public string plain_range (TextPos a, TextPos b) {
            return copy_range (a, b).plain_text ();
        }

        public static bool is_word_char (unichar c) {
            return c.isalnum () || c == '_' || c == '\'' || c == 0x2019;
        }

        public void word_bounds (TextPos p, out TextPos a, out TextPos b) {
            var c = clamp (p);
            string t = paras[c.para].text ();
            int n = t.char_count ();
            int s = c.offset, e = c.offset;
            while (s > 0 && is_word_char (t.get_char (t.index_of_nth_char (s - 1)))) s--;
            while (e < n && is_word_char (t.get_char (t.index_of_nth_char (e)))) e++;
            a = TextPos (c.para, s);
            b = TextPos (c.para, e);
        }

        public Gee.ArrayList<TextPos?> find_all (string needle, bool match_case, bool whole_word) {
            var list = new Gee.ArrayList<TextPos?> ();
            if (needle == "") return list;
            string n = match_case ? needle : needle.casefold ();
            int nlen = needle.char_count ();
            for (int pi = 0; pi < paras.size; pi++) {
                string t = paras[pi].text ();
                string hay = match_case ? t : t.casefold ();
                if (hay.char_count () != t.char_count ()) hay = t;
                int from = 0;
                while (true) {
                    int bi = hay.index_of (n, from);
                    if (bi < 0) break;
                    from = bi + n.length;
                    int ci = hay.substring (0, bi).char_count ();
                    if (whole_word) {
                        if (ci > 0 && is_word_char (t.get_char (t.index_of_nth_char (ci - 1)))) continue;
                        int after = ci + nlen;
                        if (after < t.char_count () && is_word_char (t.get_char (t.index_of_nth_char (after)))) continue;
                    }
                    list.add (TextPos (pi, ci));
                }
            }
            return list;
        }

        public int replace_all (string needle, string replacement, bool match_case, bool whole_word) {
            var found = find_all (needle, match_case, whole_word);
            int nlen = needle.char_count ();
            for (int i = found.size - 1; i >= 0; i--) {
                var a = found[i];
                var b = TextPos (a.para, a.offset + nlen);
                var tmpl = format_at (TextPos (a.para, a.offset + 1)).clone ();
                delete_range (a, b);
                if (replacement != "") insert_text (a, replacement, tmpl);
            }
            return found.size;
        }

        public Run? note_near (TextPos p) {
            if (p.para < 0 || p.para >= paras.size) return null;
            var para = paras[p.para];
            int pos = 0;
            foreach (var r in para.runs) {
                int n = r.length ();
                if (r.note != null && (p.offset == pos || p.offset == pos + n)) return r;
                pos += n;
            }
            return null;
        }

        public TextPos insert_run (TextPos at, Run run) {
            var pos = clamp (at);
            var fmt = format_at (pos);
            var para = paras[pos.para];
            int idx = para.split_at (pos.offset);
            run.cstyle = fmt.cstyle;
            run.fmt = fmt.fmt.clone ();
            para.runs.insert (idx, run);
            para.normalize ();
            return TextPos (pos.para, pos.offset + run.length ());
        }

        public Run? anchor_near (TextPos p) {
            if (p.para < 0 || p.para >= paras.size) return null;
            var para = paras[p.para];
            int pos = 0;
            foreach (var r in para.runs) {
                int n = r.length ();
                if (r.anchor != null && (p.offset == pos || p.offset == pos + n)) return r;
                pos += n;
            }
            return null;
        }

        public Gee.ArrayList<string> fields () {
            var list = new Gee.ArrayList<string> ();
            foreach (var p in paras) foreach (var r in p.runs) if (r.field != "" && !list.contains (r.field)) list.add (r.field);
            return list;
        }
    }
}
