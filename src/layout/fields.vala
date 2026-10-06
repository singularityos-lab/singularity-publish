namespace Singularity.Apps.Publish {

    public class Fields {
        public const string PAGE = "page";
        public const string PAGES = "pages";
        public const string SECTION = "section";
        public const string DATE = "date";
        public const string TITLE = "title";
        public const string NEXT_PAGE = "next-page";
        public const string PREV_PAGE = "prev-page";
        public const string MERGE_PREFIX = "merge:";
        public const string BIZ_PREFIX = "biz:";
        public const string TIME = "time";
        public const string VAR_PREFIX = "var:";
        public const string XREF_PREFIX = "xref:";

        public static string xref (int format, string anchor) {
            return "%s%d:%s".printf (XREF_PREFIX, format, anchor);
        }

        public static bool parse_xref (string field, out int format, out string anchor) {
            format = 0;
            anchor = "";
            if (!field.has_prefix (XREF_PREFIX)) return false;
            string rest = field.substring (XREF_PREFIX.length);
            int c = rest.index_of_char (':');
            if (c < 0) return false;
            format = int.parse (rest.substring (0, c));
            anchor = rest.substring (c + 1);
            return true;
        }

        public static string[] xref_formats () {
            return { _("Full Paragraph and Page Number"), _("Full Paragraph"), _("Page Number"), _("Paragraph Number"), _("Paragraph Text"), _("Text Anchor Name"), _("On Page Number") };
        }

        public static string variable (string name) {
            return VAR_PREFIX + name;
        }

        public static string label (string field) {
            if (field.has_prefix (MERGE_PREFIX)) return "«%s»".printf (field.substring (MERGE_PREFIX.length));
            if (field.has_prefix (BIZ_PREFIX)) return BusinessInfo.label (field.substring (BIZ_PREFIX.length));
            if (field.has_prefix (VAR_PREFIX)) return "<%s>".printf (field.substring (VAR_PREFIX.length));
            if (field.has_prefix (XREF_PREFIX)) return _("Cross-Reference");
            if (field.has_prefix ("idx:")) return _("Index Entry");
            switch (field) {
                case TIME: return _("Time");
                case PAGE: return _("Page Number");
                case PAGES: return _("Page Count");
                case SECTION: return _("Section Name");
                case DATE: return _("Date");
                case TITLE: return _("Title");
                case NEXT_PAGE: return _("Continued on Page");
                case PREV_PAGE: return _("Continued from Page");
                default: return field;
            }
        }

        public static string merge (string name) {
            return MERGE_PREFIX + name;
        }

        public static string biz (string key) {
            return BIZ_PREFIX + key;
        }

        public static bool is_merge (string field) {
            return field.has_prefix (MERGE_PREFIX);
        }

        public static string merge_name (string field) {
            return field.has_prefix (MERGE_PREFIX) ? field.substring (MERGE_PREFIX.length) : "";
        }
    }

    public delegate string? RunningLookup (string style, bool last, int page_index);

    public delegate bool XrefLookup (string anchor, out int page, out string number, out string text);

    public class FieldContext {
        public unowned RunningLookup? running = null;
        public Publication pub;
        public int page_index = -1;
        public string master_id = "";
        public int record = -1;
        public int next_page = -1;
        public int prev_page = -1;
        public DateTime? now = null;
        public Gee.Map<Story, int>? note_numbers = null;
        public unowned XrefLookup? xref = null;

        public FieldContext (Publication pub) {
            this.pub = pub;
        }

        public FieldContext copy () {
            var c = new FieldContext (pub);
            c.page_index = page_index;
            c.master_id = master_id;
            c.record = record;
            c.next_page = next_page;
            c.prev_page = prev_page;
            c.now = now;
            c.running = running;
            c.note_numbers = note_numbers;
            c.xref = xref;
            return c;
        }

        public Gee.Map<Story, int>? endnote_numbers = null;

        public int endnote_number (Story note) {
            if (endnote_numbers == null) endnote_numbers = Footnotes.number_endnotes (pub);
            return endnote_numbers.has_key (note) ? endnote_numbers[note] : 1;
        }

        public int note_number (Story note) {
            if (note_numbers == null) note_numbers = Footnotes.number_all (pub);
            return note_numbers.has_key (note) ? note_numbers[note] : 1;
        }

        public int xref_page (string field) {
            int fmt, page;
            string anchor, number, text;
            if (!Fields.parse_xref (field, out fmt, out anchor) || xref == null) return -1;
            if (!xref (anchor, out page, out number, out text)) return -1;
            return page;
        }

        public string resolve_xref (string field) {
            int fmt, page = -1;
            string anchor, number = "", text = "";
            Fields.parse_xref (field, out fmt, out anchor);
            bool found = xref != null && xref (anchor, out page, out number, out text);
            if (!found) {
                bool exists = false;
                foreach (var st in pub.stories.values) foreach (var p in st.paras) if (p.anchor == anchor) {
                    exists = true;
                    if (text == "") text = p.text ().replace (OBJ_STR, "").strip ();
                }
                if (!exists) return _("[missing: %s]").printf (anchor);
            }
            string pg = page >= 0 ? pub.page_label (page) : "#";
            switch (fmt) {
                case 1: return text;
                case 2: return pg;
                case 3: return number != "" ? number : text;
                case 4: return text;
                case 5: return anchor;
                case 6: return _("on page %s").printf (pg);
                default: return _("“%s” on page %s").printf (text, pg);
            }
        }

        public string resolve (string field) {
            if (field.has_prefix (Fields.XREF_PREFIX)) return resolve_xref (field);
            if (field.has_prefix (IndexMarker.PREFIX)) return "";
            if (Fields.is_merge (field)) {
                string name = Fields.merge_name (field);
                int rec = record >= 0 ? record : pub.merge.preview;
                if (rec < 0 || rec >= pub.merge.records.size) return "«%s»".printf (name);
                return pub.merge.value (rec, name);
            }
            if (field.has_prefix (Fields.VAR_PREFIX)) return variable (field.substring (Fields.VAR_PREFIX.length));
            if (field.has_prefix (Fields.BIZ_PREFIX)) {
                string key = field.substring (Fields.BIZ_PREFIX.length);
                string v = pub.business.get (key);
                return v != "" ? v.replace ("\n", "\u2028").replace ("\r", "") : "";
            }
            switch (field) {
                case Fields.TIME:
                    var t = now ?? new DateTime.now_local ();
                    return t.format ("%X");
                case Fields.PAGE:
                    if (page_index < 0) return master_id != "" ? master_id : "#";
                    return pub.page_label (page_index);
                case Fields.PAGES:
                    return pub.pages.size.to_string ();
                case Fields.SECTION:
                    if (page_index < 0) return _("Section");
                    return pub.section_for (page_index).name;
                case Fields.DATE:
                    var d = now ?? new DateTime.now_local ();
                    return d.format ("%x");
                case Fields.TITLE:
                    return pub.meta.title;
                case Fields.NEXT_PAGE:
                    return next_page >= 0 ? pub.page_label (next_page) : "#";
                case Fields.PREV_PAGE:
                    return prev_page >= 0 ? pub.page_label (prev_page) : "#";
                default:
                    return "";
            }
        }

        private static string date_of (string iso) {
            if (iso == "") return "";
            var d = new DateTime.from_iso8601 (iso, new TimeZone.utc ());
            if (d == null) return iso;
            return d.to_local ().format ("%x");
        }

        public string variable (string name) {
            var v = pub.text_var (name);
            if (v == null) return "";
            string body;
            switch (v.kind) {
                case "running":
                    if (page_index < 0 || running == null) body = "<%s>".printf (v.style);
                    else body = running (v.style, v.use_last, page_index) ?? "";
                    break;
                case "file":
                    body = pub.file_name != "" ? pub.file_name : pub.meta.title;
                    break;
                case "modified":
                    body = date_of (pub.meta.modified);
                    break;
                case "created":
                    body = date_of (pub.meta.created);
                    break;
                case "output":
                    body = (now ?? new DateTime.now_local ()).format ("%x");
                    break;
                case "chapter":
                    body = pub.chapter_number.to_string ();
                    break;
                default:
                    body = v.text;
                    break;
            }
            if (body == "") return "";
            return v.before + body + v.after;
        }
    }
}
