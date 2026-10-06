namespace Singularity.Apps.Publish {

    public class XmlIn {
        public static Xml.Doc* parse (string text) throws FormatError {
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE | Xml.ParserOption.NOBLANKS);
            if (doc == null || doc->get_root_element () == null) {
                if (doc != null) delete doc;
                throw new FormatError.INVALID (_("The document contains malformed XML."));
            }
            return doc;
        }

        public static Xml.Node* child (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        public static Xml.Node* find (Xml.Node* n, string path) {
            Xml.Node* cur = n;
            foreach (string part in path.split ("/")) {
                cur = child (cur, part);
                if (cur == null) return null;
            }
            return cur;
        }

        public static Gee.ArrayList<Xml.Node*> elements (Xml.Node* n, string? name = null) {
            var list = new Gee.ArrayList<Xml.Node*> ();
            if (n == null) return list;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (name == null || c->name == name) list.add (c);
            }
            return list;
        }

        public static string? attr (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->name == name && a->ns == null) return a->children != null ? a->children->content : "";
            }
            return null;
        }

        public static string? attr_ns (Xml.Node* n, string name, string ns_suffix) {
            if (n == null) return null;
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->name == name && a->ns != null && a->ns->href != null && (a->ns->href == ns_suffix || a->ns->href.has_suffix (ns_suffix))) {
                    return a->children != null ? a->children->content : "";
                }
            }
            return null;
        }

        public static string? attr_any (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->name == name) return a->children != null ? a->children->content : "";
            }
            return null;
        }

        public static string ns_of (Xml.Node* n) {
            return n != null && n->ns != null && n->ns->href != null ? n->ns->href : "";
        }

        public static int int_attr (Xml.Node* n, string name, int fallback) {
            string? v = attr (n, name);
            if (v == null) return fallback;
            int64 r;
            if (int64.try_parse (v.strip (), out r)) return (int) r;
            return fallback;
        }

        public static double double_attr (Xml.Node* n, string name, double fallback) {
            string? v = attr (n, name);
            if (v == null) return fallback;
            double r;
            if (double.try_parse (v.strip (), out r)) return r;
            return fallback;
        }

        public static bool bool_attr (Xml.Node* n, string name, bool fallback) {
            string? v = attr (n, name);
            if (v == null) return fallback;
            return v == "1" || v == "true" || v == "on";
        }

        public static string text (Xml.Node* n) {
            if (n == null) return "";
            string? c = n->get_content ();
            return c ?? "";
        }
    }

    public class XmlOut {
        public StringBuilder sb = new StringBuilder ();
        private Gee.ArrayList<string> stack = new Gee.ArrayList<string> ();
        private bool open_tag = false;

        public XmlOut (bool declaration = true) {
            if (declaration) sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
        }

        public static string esc (string s) {
            var b = new StringBuilder.sized (s.length + 8);
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                switch (c) {
                    case '&': b.append ("&amp;"); break;
                    case '<': b.append ("&lt;"); break;
                    case '>': b.append ("&gt;"); break;
                    case '"': b.append ("&quot;"); break;
                    default:
                        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') break;
                        if (c == 0xFFFE || c == 0xFFFF) break;
                        b.append_unichar (c);
                        break;
                }
            }
            return b.str;
        }

        private void close_open () {
            if (open_tag) {
                sb.append (">");
                open_tag = false;
            }
        }

        public XmlOut start (string tag) {
            close_open ();
            sb.append ("<");
            sb.append (tag);
            stack.add (tag);
            open_tag = true;
            return this;
        }

        public XmlOut a (string name, string val) {
            sb.append (" ");
            sb.append (name);
            sb.append ("=\"");
            sb.append (esc (val));
            sb.append ("\"");
            return this;
        }

        public XmlOut ai (string name, int64 val) {
            return a (name, val.to_string ());
        }

        public XmlOut ad (string name, double val) {
            return a (name, num (val));
        }

        public static string num (double v) {
            if (v == Math.floor (v) && Math.fabs (v) < 1e15) return "%.0f".printf (v);
            string s = "%.4f".printf (v);
            if (s.contains (",")) s = s.replace (",", ".");
            while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
            if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
            return s;
        }

        public XmlOut text (string t) {
            close_open ();
            sb.append (esc (t));
            return this;
        }

        public XmlOut raw (string t) {
            close_open ();
            sb.append (t);
            return this;
        }

        public XmlOut end () {
            string tag = stack.remove_at (stack.size - 1);
            if (open_tag) {
                sb.append ("/>");
                open_tag = false;
            } else {
                sb.append ("</");
                sb.append (tag);
                sb.append (">");
            }
            return this;
        }

        public XmlOut empty (string tag) {
            start (tag);
            return end ();
        }

        public XmlOut element (string tag, string content) {
            start (tag);
            text (content);
            return end ();
        }

        public string finish () {
            while (stack.size > 0) end ();
            return sb.str;
        }
    }
}
