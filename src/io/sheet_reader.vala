namespace Singularity.Apps.Publish {

    public class SheetReader {
        public static Gee.ArrayList<string> sheet_names (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var zip = new ZipReader (data);
            var names = new Gee.ArrayList<string> ();
            if (zip.has ("xl/workbook.xml")) {
                Xml.Doc* d = XmlIn.parse (zip.read_text ("xl/workbook.xml"));
                foreach (var s in XmlIn.elements (XmlIn.child (d->get_root_element (), "sheets"), "sheet")) names.add (XmlIn.attr_any (s, "name") ?? "");
                delete d;
                return names;
            }
            if (zip.has ("content.xml")) {
                Xml.Doc* d = XmlIn.parse (zip.read_text ("content.xml"));
                var sheet = XmlIn.child (XmlIn.child (d->get_root_element (), "body"), "spreadsheet");
                foreach (var t in XmlIn.elements (sheet, "table")) names.add (XmlIn.attr_any (t, "name") ?? "");
                delete d;
                return names;
            }
            throw new FormatError.INVALID (_("The file is not an Excel or OpenDocument spreadsheet."));
        }

        public static DataTable read (string path, int sheet = 0, bool header = true) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var rows = read_rows (data, sheet);
            return to_table (rows, header);
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> read_rows (uint8[] data, int sheet) throws Error {
            var zip = new ZipReader (data);
            if (zip.has ("xl/workbook.xml")) return xlsx_rows (zip, sheet);
            if (zip.has ("content.xml")) return ods_rows (zip, sheet);
            throw new FormatError.INVALID (_("The file is not an Excel or OpenDocument spreadsheet."));
        }

        public static DataTable to_table (Gee.ArrayList<Gee.ArrayList<string>> rows, bool header) {
            var sb = new StringBuilder ();
            var t = new DataTable ();
            while (rows.size > 0) {
                bool empty = true;
                foreach (string v in rows[rows.size - 1]) if (v.strip () != "") empty = false;
                if (!empty) break;
                rows.remove_at (rows.size - 1);
            }
            int width = 0;
            foreach (var r in rows) {
                int last = -1;
                for (int i = 0; i < r.size; i++) if (r[i].strip () != "") last = i;
                width = int.max (width, last + 1);
            }
            if (rows.size == 0 || width == 0) return t;
            int start = 0;
            if (header) {
                for (int i = 0; i < width; i++) {
                    string name = i < rows[0].size ? rows[0][i].strip () : "";
                    if (name == "") name = _("Field %d").printf (i + 1);
                    string unique = name;
                    int k = 2;
                    while (t.fields.contains (unique)) unique = "%s %d".printf (name, k++);
                    t.fields.add (unique);
                }
                start = 1;
            } else {
                for (int i = 0; i < width; i++) t.fields.add (_("Field %d").printf (i + 1));
            }
            for (int r = start; r < rows.size; r++) {
                var rec = new Gee.ArrayList<string> ();
                bool any = false;
                for (int i = 0; i < width; i++) {
                    string v = i < rows[r].size ? rows[r][i] : "";
                    if (v.strip () != "") any = true;
                    rec.add (v);
                }
                if (any) t.records.add (rec);
            }
            sb.truncate ();
            return t;
        }

        public static int column_index (string cell_ref) {
            int col = 0;
            for (int i = 0; i < cell_ref.length; i++) {
                char c = cell_ref[i];
                if (c >= 'A' && c <= 'Z') col = col * 26 + (c - 'A' + 1);
                else if (c >= 'a' && c <= 'z') col = col * 26 + (c - 'a' + 1);
                else break;
            }
            return col - 1;
        }

        private static bool is_date_format (int id, string? code) {
            if ((id >= 14 && id <= 22) || (id >= 45 && id <= 47) || (id >= 27 && id <= 36) || (id >= 50 && id <= 58)) return true;
            if (code == null) return false;
            var sb = new StringBuilder ();
            bool quoted = false;
            for (int i = 0; i < code.length; i++) {
                char c = code[i];
                if (c == '"') {
                    quoted = !quoted;
                    continue;
                }
                if (quoted || c == '\\') continue;
                if (c == '[') {
                    while (i < code.length && code[i] != ']') i++;
                    continue;
                }
                sb.append_c (c.tolower ());
            }
            string s = sb.str;
            return s.contains ("d") || s.contains ("yy") || (s.contains ("m") && (s.contains ("h") || s.contains ("s")));
        }

        public static string excel_date (double serial, bool date1904) {
            double days = serial;
            var epoch = date1904 ? new DateTime.utc (1904, 1, 1, 0, 0, 0) : new DateTime.utc (1899, 12, 30, 0, 0, 0);
            var dt = epoch.add_seconds (days * 86400.0);
            bool has_time = Math.fabs (serial - Math.floor (serial)) > 1e-9;
            bool has_date = serial >= 1;
            if (has_date && has_time) return dt.format ("%Y-%m-%d %H:%M");
            if (has_time && !has_date) return dt.format ("%H:%M");
            return dt.format ("%Y-%m-%d");
        }

        private static string number_text (string v) {
            double d;
            if (!double.try_parse (v, out d)) return v;
            if (d == Math.floor (d) && Math.fabs (d) < 1e15) return "%.0f".printf (d);
            string s = "%.10g".printf (d);
            return s;
        }

        private static string rich_text (Xml.Node* si) {
            var sb = new StringBuilder ();
            foreach (var c in XmlIn.elements (si)) {
                if (c->name == "t") sb.append (XmlIn.text (c));
                else if (c->name == "r") {
                    var t = XmlIn.child (c, "t");
                    if (t != null) sb.append (XmlIn.text (t));
                }
            }
            return sb.str;
        }

        private static Gee.ArrayList<Gee.ArrayList<string>> xlsx_rows (ZipReader zip, int sheet) throws Error {
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            Xml.Doc* wb = XmlIn.parse (zip.read_text ("xl/workbook.xml"));
            var wroot = wb->get_root_element ();
            bool date1904 = false;
            var pr = XmlIn.child (wroot, "workbookPr");
            if (pr != null) date1904 = (XmlIn.attr_any (pr, "date1904") ?? "0") == "1" || (XmlIn.attr_any (pr, "date1904") ?? "") == "true";
            var sheets = XmlIn.elements (XmlIn.child (wroot, "sheets"), "sheet");
            if (sheets.size == 0) {
                delete wb;
                throw new FormatError.INVALID (_("The workbook has no sheets."));
            }
            var target_sheet = sheets[sheet.clamp (0, sheets.size - 1)];
            string rid = XmlIn.attr_any (target_sheet, "id") ?? "";
            delete wb;
            string target = "worksheets/sheet%d.xml".printf (sheet + 1);
            string? rels = zip.read_text ("xl/_rels/workbook.xml.rels");
            if (rels != null) {
                Xml.Doc* rd = XmlIn.parse (rels);
                foreach (var r in XmlIn.elements (rd->get_root_element (), "Relationship")) if ((XmlIn.attr_any (r, "Id") ?? "") == rid) target = XmlIn.attr_any (r, "Target") ?? target;
                delete rd;
            }
            string path = target.has_prefix ("/") ? target.substring (1) : "xl/" + target;
            var shared = new Gee.ArrayList<string> ();
            string? ss = zip.read_text ("xl/sharedStrings.xml");
            if (ss != null) {
                Xml.Doc* sd = NativeFormat.parse_keep_space (ss);
                foreach (var si in XmlIn.elements (sd->get_root_element (), "si")) shared.add (rich_text (si));
                delete sd;
            }
            var date_styles = new Gee.ArrayList<bool> ();
            string? styles = zip.read_text ("xl/styles.xml");
            if (styles != null) {
                Xml.Doc* st = XmlIn.parse (styles);
                var codes = new Gee.HashMap<int, string> ();
                foreach (var nf in XmlIn.elements (XmlIn.child (st->get_root_element (), "numFmts"), "numFmt")) codes[XmlIn.int_attr (nf, "numFmtId", 0)] = XmlIn.attr_any (nf, "formatCode") ?? "";
                foreach (var xf in XmlIn.elements (XmlIn.child (st->get_root_element (), "cellXfs"), "xf")) {
                    int id = XmlIn.int_attr (xf, "numFmtId", 0);
                    date_styles.add (is_date_format (id, codes.has_key (id) ? codes[id] : null));
                }
                delete st;
            }
            string? xml = zip.read_text (path);
            if (xml == null) throw new FormatError.INVALID (_("The sheet \"%s\" could not be read.").printf (path));
            Xml.Doc* d = NativeFormat.parse_keep_space (xml);
            var data = XmlIn.child (d->get_root_element (), "sheetData");
            int next_row = 0;
            foreach (var rn in XmlIn.elements (data, "row")) {
                int rnum = XmlIn.int_attr (rn, "r", next_row + 1) - 1;
                while (rows.size < rnum && rows.size < 100000) rows.add (new Gee.ArrayList<string> ());
                var row = new Gee.ArrayList<string> ();
                int next_col = 0;
                foreach (var cn in XmlIn.elements (rn, "c")) {
                    string? r = XmlIn.attr_any (cn, "r");
                    int col = r != null ? column_index (r) : next_col;
                    while (row.size < col && row.size < 16384) row.add ("");
                    string type = XmlIn.attr_any (cn, "t") ?? "n";
                    var vn = XmlIn.child (cn, "v");
                    string v = vn != null ? XmlIn.text (vn) : "";
                    string text;
                    switch (type) {
                        case "s":
                            int idx = int.parse (v);
                            text = idx >= 0 && idx < shared.size ? shared[idx] : "";
                            break;
                        case "inlineStr":
                            var isn = XmlIn.child (cn, "is");
                            text = isn != null ? rich_text (isn) : "";
                            break;
                        case "b":
                            text = v == "1" ? "TRUE" : "FALSE";
                            break;
                        case "str":
                        case "e":
                            text = v;
                            break;
                        default:
                            int sidx = XmlIn.int_attr (cn, "s", 0);
                            if (v != "" && sidx >= 0 && sidx < date_styles.size && date_styles[sidx]) text = excel_date (Units.parse_num (v, 0), date1904);
                            else text = number_text (v);
                            break;
                    }
                    row.add (text);
                    next_col = col + 1;
                }
                rows.add (row);
                next_row = rnum + 1;
            }
            delete d;
            return rows;
        }

        private static string ods_cell_text (Xml.Node* cell) {
            string type = XmlIn.attr_any (cell, "value-type") ?? "";
            if (type == "date") {
                string? dv = XmlIn.attr_any (cell, "date-value");
                if (dv != null) return dv.length > 10 && dv.has_suffix ("T00:00:00") ? dv.substring (0, 10) : dv.replace ("T", " ");
            }
            var sb = new StringBuilder ();
            bool first = true;
            foreach (var p in XmlIn.elements (cell, "p")) {
                if (!first) sb.append ("\n");
                first = false;
                sb.append (ods_text (p));
            }
            if (sb.len == 0) {
                string? v = XmlIn.attr_any (cell, "value");
                if (v != null) return number_text (v);
            }
            return sb.str;
        }

        private static string ods_text (Xml.Node* n) {
            var sb = new StringBuilder ();
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE) sb.append (c->content ?? "");
                else if (c->type == Xml.ElementType.ELEMENT_NODE) {
                    if (c->name == "s") sb.append (string.nfill (int.max (1, int.parse (XmlIn.attr_any (c, "c") ?? "1")), ' '));
                    else if (c->name == "tab") sb.append ("\t");
                    else if (c->name == "line-break") sb.append ("\n");
                    else sb.append (ods_text (c));
                }
            }
            return sb.str;
        }

        private static Gee.ArrayList<Gee.ArrayList<string>> ods_rows (ZipReader zip, int sheet) throws Error {
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            Xml.Doc* d = NativeFormat.parse_keep_space (zip.read_text ("content.xml"));
            var ss = XmlIn.child (XmlIn.child (d->get_root_element (), "body"), "spreadsheet");
            var tables = XmlIn.elements (ss, "table");
            if (tables.size == 0) {
                delete d;
                throw new FormatError.INVALID (_("The spreadsheet has no sheets."));
            }
            var table = tables[sheet.clamp (0, tables.size - 1)];
            var row_nodes = new Gee.ArrayList<Xml.Node*> ();
            foreach (var c in XmlIn.elements (table)) {
                if (c->name == "table-row") row_nodes.add (c);
                else if (c->name == "table-header-rows" || c->name == "table-row-group" || c->name == "table-rows") foreach (var r in XmlIn.elements (c, "table-row")) row_nodes.add (r);
            }
            foreach (var rn in row_nodes) {
                int repeat = int.parse (XmlIn.attr_any (rn, "number-rows-repeated") ?? "1").clamp (1, 100000);
                var row = new Gee.ArrayList<string> ();
                foreach (var cn in XmlIn.elements (rn)) {
                    if (cn->name != "table-cell" && cn->name != "covered-table-cell") continue;
                    int crep = int.parse (XmlIn.attr_any (cn, "number-columns-repeated") ?? "1").clamp (1, 16384);
                    string text = cn->name == "table-cell" ? ods_cell_text (cn) : "";
                    if (text == "" && crep > 64) crep = 1;
                    for (int k = 0; k < crep && row.size < 16384; k++) row.add (text);
                }
                bool empty = true;
                foreach (string v in row) if (v != "") empty = false;
                if (empty && repeat > 64) repeat = 1;
                for (int k = 0; k < repeat && rows.size < 200000; k++) {
                    var copy = new Gee.ArrayList<string> ();
                    copy.add_all (row);
                    rows.add (copy);
                }
            }
            delete d;
            return rows;
        }
    }
}
