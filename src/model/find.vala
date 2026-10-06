namespace Singularity.Apps.Publish {

    public class FindFormat {
        public string para_style = "";
        public string char_style = "";
        public string? font = null;
        public double size = double.NAN;
        public int bold = -1;
        public int italic = -1;
        public int underline = -1;
        public string? color = null;

        public bool is_empty () {
            return para_style == "" && char_style == "" && font == null && size.is_nan () && bold < 0 && italic < 0 && underline < 0 && color == null;
        }

        public bool matches (Publication pub, Paragraph para, Run run) {
            if (para_style != "" && para.style != para_style) return false;
            if (char_style != "" && run.cstyle != char_style) return false;
            if (font == null && size.is_nan () && bold < 0 && italic < 0 && underline < 0 && color == null) return true;
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (para.style, pf, cf);
            if (run.cstyle != "") pub.styles.resolve_character (run.cstyle, cf);
            cf.apply (run.fmt);
            if (font != null && (cf.font ?? "").down () != font.down ()) return false;
            if (!size.is_nan () && Math.fabs (cf.size - size) > 0.05) return false;
            if (bold >= 0 && (cf.bold == 1 ? 1 : 0) != bold) return false;
            if (italic >= 0 && (cf.italic == 1 ? 1 : 0) != italic) return false;
            if (underline >= 0 && (cf.underline == 1 ? 1 : 0) != underline) return false;
            if (color != null && cf.color != color) return false;
            return true;
        }

        public void apply_to_run (Run run) {
            if (char_style != "") run.cstyle = char_style;
            if (font != null) run.fmt.font = font;
            if (!size.is_nan ()) run.fmt.size = size;
            if (bold >= 0) run.fmt.bold = bold;
            if (italic >= 0) run.fmt.italic = italic;
            if (underline >= 0) run.fmt.underline = underline;
            if (color != null) run.fmt.color = color;
        }
    }

    public class FindQuery {
        public string pattern = "";
        public bool grep = false;
        public bool match_case = false;
        public bool whole_word = false;
        public bool change_text = true;
        public string replacement = "";
        public FindFormat find_fmt = new FindFormat ();
        public FindFormat change_fmt = new FindFormat ();
    }

    public class FindMatch {
        public Story story;
        public TextPos a;
        public TextPos b;
        public string[] groups;

        public FindMatch (Story story, TextPos a, TextPos b, string[] groups) {
            this.story = story;
            this.a = a;
            this.b = b;
            this.groups = groups;
        }
    }

    public class ObjectQuery {
        public int kind = -1;
        public string fill = "";
        public string stroke = "";
        public string object_style = "";
        public string change_object_style = "";
        public string change_fill = "";
        public string change_stroke = "";

        public bool matches (Item it) {
            if (kind >= 0 && (int) it.kind != kind) return false;
            if (fill != "" && (it.fill.kind == FillKind.NONE || it.fill.color != fill)) return false;
            if (stroke != "" && it.stroke.color != stroke) return false;
            if (object_style != "" && it.object_style != object_style) return false;
            return true;
        }
    }

    public class Finder {
        public static Regex? compile (FindQuery q) throws RegexError {
            if (q.pattern == "") return null;
            string pat = q.grep ? q.pattern : Regex.escape_string (q.pattern);
            if (!q.grep && q.whole_word) pat = "(?<![\\w'’])" + pat + "(?![\\w'’])";
            var flags = RegexCompileFlags.OPTIMIZE;
            if (!q.match_case) flags |= RegexCompileFlags.CASELESS;
            return new Regex (pat, flags);
        }

        private static Run? run_at (Paragraph p, int offset) {
            int pos = 0;
            foreach (var r in p.runs) {
                int n = r.text.char_count ();
                if (offset < pos + n) return r;
                pos += n;
            }
            return p.runs.size > 0 ? p.runs[p.runs.size - 1] : null;
        }

        public static Gee.ArrayList<FindMatch> search (Publication pub, Story story, FindQuery q) throws RegexError {
            var list = new Gee.ArrayList<FindMatch> ();
            var rx = compile (q);
            for (int pi = 0; pi < story.paras.size; pi++) {
                var para = story.paras[pi];
                string text = para.text ();
                if (rx == null) {
                    if (q.find_fmt.is_empty ()) continue;
                    int off = 0;
                    int start = -1;
                    var buf = new StringBuilder ();
                    foreach (var r in para.runs) {
                        int n = r.text.char_count ();
                        bool ok = n > 0 && r.field == "" && q.find_fmt.matches (pub, para, r);
                        if (ok) {
                            if (start < 0) start = off;
                            buf.append (r.text);
                        } else if (start >= 0) {
                            list.add (new FindMatch (story, TextPos (pi, start), TextPos (pi, off), { buf.str }));
                            start = -1;
                            buf.truncate ();
                        }
                        off += n;
                    }
                    if (start >= 0) list.add (new FindMatch (story, TextPos (pi, start), TextPos (pi, off), { buf.str }));
                    continue;
                }
                MatchInfo mi;
                if (!rx.match_full (text, -1, 0, 0, out mi)) continue;
                while (mi.matches ()) {
                    int sb, eb;
                    mi.fetch_pos (0, out sb, out eb);
                    if (eb > sb) {
                        int ca = text.substring (0, sb).char_count ();
                        int cb = ca + text.substring (sb, eb - sb).char_count ();
                        var r = run_at (para, ca);
                        if (r != null && q.find_fmt.matches (pub, para, r)) list.add (new FindMatch (story, TextPos (pi, ca), TextPos (pi, cb), mi.fetch_all ()));
                    }
                    try {
                        if (!mi.next ()) break;
                    } catch (RegexError e) {
                        break;
                    }
                }
            }
            return list;
        }

        public static string expand (string repl, string[] groups, bool grep) {
            if (!grep) return repl;
            var sb = new StringBuilder ();
            int i = 0;
            while (i < repl.length) {
                char c = repl[i];
                if (c == '$' && i + 1 < repl.length && repl[i + 1].isdigit ()) {
                    int g = repl[i + 1] - '0';
                    if (g < groups.length) sb.append (groups[g] ?? "");
                    i += 2;
                    continue;
                }
                if (c == '\\' && i + 1 < repl.length) {
                    char d = repl[i + 1];
                    if (d == 'n') sb.append_c ('\n');
                    else if (d == 't') sb.append_c ('\t');
                    else sb.append_c (d);
                    i += 2;
                    continue;
                }
                sb.append_c (c);
                i++;
            }
            return sb.str;
        }

        public static void replace_match (Publication pub, FindMatch m, FindQuery q) {
            var story = m.story;
            TextPos a = m.a, b = m.b;
            if (q.change_text) {
                string rep = expand (q.replacement, m.groups, q.grep);
                var tmpl = story.format_at (TextPos (a.para, a.offset + 1)).clone ();
                story.delete_range (a, b);
                if (rep != "") {
                    var end = story.insert_text (a, rep, tmpl);
                    b = end;
                } else {
                    b = a;
                }
            }
            if (!q.change_fmt.is_empty () && a.compare (b) != 0) {
                story.apply_chars (a, b, (r) => q.change_fmt.apply_to_run (r));
            }
            if (q.change_fmt.para_style != "" && pub.styles.find_paragraph (q.change_fmt.para_style) != null) {
                for (int pi = a.para; pi <= b.para && pi < story.paras.size; pi++) story.paras[pi].style = q.change_fmt.para_style;
            }
        }

        public static int replace_all (Publication pub, Gee.List<Story> stories, FindQuery q) throws RegexError {
            int total = 0;
            foreach (var s in stories) {
                var found = search (pub, s, q);
                for (int i = found.size - 1; i >= 0; i--) {
                    replace_match (pub, found[i], q);
                    total++;
                }
            }
            return total;
        }

        public static Gee.ArrayList<Item> find_objects (Publication pub, ObjectQuery q) {
            var list = new Gee.ArrayList<Item> ();
            pub.walk ((r) => {
                if (q.matches (r.item)) list.add (r.item);
                return true;
            });
            return list;
        }

        public static int change_objects (Publication pub, ObjectQuery q) {
            var list = find_objects (pub, q);
            foreach (var it in list) {
                if (q.change_object_style != "") {
                    var os = pub.object_style (q.change_object_style);
                    if (os != null) os.apply_to (pub, it);
                }
                if (q.change_fill != "") it.fill = new Fill.solid (q.change_fill);
                if (q.change_stroke != "") it.stroke.color = q.change_stroke;
            }
            return list.size;
        }
    }
}
