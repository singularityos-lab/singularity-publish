namespace Singularity.Apps.Publish {

    public class CellStyle {
        public string name;
        public string based_on = "";
        public string fill = "";
        public int valign = -1;
        public int diagonal = -1;
        public string para_style = "";

        public CellStyle (string name) {
            this.name = name;
        }

        public CellStyle clone () {
            var c = new CellStyle (name);
            c.based_on = based_on;
            c.fill = fill;
            c.valign = valign;
            c.diagonal = diagonal;
            c.para_style = para_style;
            return c;
        }

        public void write (XmlOut x) {
            x.start ("cell-style").a ("name", name).a ("based-on", based_on).a ("fill", fill).ai ("valign", valign).ai ("diagonal", diagonal).a ("para-style", para_style).end ();
        }

        public static CellStyle read (Xml.Node* n) {
            var c = new CellStyle (XmlIn.attr (n, "name") ?? "");
            c.based_on = XmlIn.attr (n, "based-on") ?? "";
            c.fill = XmlIn.attr (n, "fill") ?? "";
            c.valign = XmlIn.int_attr (n, "valign", -1);
            c.diagonal = XmlIn.int_attr (n, "diagonal", -1);
            c.para_style = XmlIn.attr (n, "para-style") ?? "";
            return c;
        }
    }

    public class TableStyle {
        public string name;
        public string based_on = "";
        public string border_color = "";
        public double border_width = -1;
        public string header_fill = "";
        public string alt_fill = "";
        public double cell_inset = -1;
        public string header_cell = "";
        public string body_cell = "";
        public string first_col_cell = "";
        public int repeat_header = -1;

        public TableStyle (string name) {
            this.name = name;
        }

        public TableStyle clone () {
            var t = new TableStyle (name);
            t.based_on = based_on;
            t.border_color = border_color;
            t.border_width = border_width;
            t.header_fill = header_fill;
            t.alt_fill = alt_fill;
            t.cell_inset = cell_inset;
            t.header_cell = header_cell;
            t.body_cell = body_cell;
            t.first_col_cell = first_col_cell;
            t.repeat_header = repeat_header;
            return t;
        }

        public void write (XmlOut x) {
            x.start ("table-style").a ("name", name).a ("based-on", based_on).a ("border-color", border_color).ad ("border-width", border_width).a ("header-fill", header_fill).a ("alt-fill", alt_fill);
            x.ad ("inset", cell_inset).a ("header-cell", header_cell).a ("body-cell", body_cell).a ("first-col-cell", first_col_cell).ai ("repeat-header", repeat_header).end ();
        }

        public static TableStyle read (Xml.Node* n) {
            var t = new TableStyle (XmlIn.attr (n, "name") ?? "");
            t.based_on = XmlIn.attr (n, "based-on") ?? "";
            t.border_color = XmlIn.attr (n, "border-color") ?? "";
            t.border_width = XmlIn.double_attr (n, "border-width", -1);
            t.header_fill = XmlIn.attr (n, "header-fill") ?? "";
            t.alt_fill = XmlIn.attr (n, "alt-fill") ?? "";
            t.cell_inset = XmlIn.double_attr (n, "inset", -1);
            t.header_cell = XmlIn.attr (n, "header-cell") ?? "";
            t.body_cell = XmlIn.attr (n, "body-cell") ?? "";
            t.first_col_cell = XmlIn.attr (n, "first-col-cell") ?? "";
            t.repeat_header = XmlIn.int_attr (n, "repeat-header", -1);
            return t;
        }
    }

    public class TableStyles {
        public static TableStyle? find_table (Publication pub, string name) {
            foreach (var t in pub.table_styles) if (t.name == name) return t;
            return null;
        }

        public static CellStyle? find_cell (Publication pub, string name) {
            foreach (var c in pub.cell_styles) if (c.name == name) return c;
            return null;
        }

        public static TableStyle resolve_table (Publication pub, string name) {
            var chain = new Gee.ArrayList<TableStyle> ();
            var seen = new Gee.HashSet<string> ();
            string cur = name;
            while (cur != "" && seen.add (cur)) {
                var s = find_table (pub, cur);
                if (s == null) break;
                chain.insert (0, s);
                cur = s.based_on;
            }
            var r = new TableStyle (name);
            foreach (var s in chain) {
                if (s.border_color != "") r.border_color = s.border_color;
                if (s.border_width >= 0) r.border_width = s.border_width;
                if (s.header_fill != "") r.header_fill = s.header_fill;
                if (s.alt_fill != "") r.alt_fill = s.alt_fill;
                if (s.cell_inset >= 0) r.cell_inset = s.cell_inset;
                if (s.header_cell != "") r.header_cell = s.header_cell;
                if (s.body_cell != "") r.body_cell = s.body_cell;
                if (s.first_col_cell != "") r.first_col_cell = s.first_col_cell;
                if (s.repeat_header >= 0) r.repeat_header = s.repeat_header;
            }
            return r;
        }

        public static CellStyle resolve_cell (Publication pub, string name) {
            var chain = new Gee.ArrayList<CellStyle> ();
            var seen = new Gee.HashSet<string> ();
            string cur = name;
            while (cur != "" && seen.add (cur)) {
                var s = find_cell (pub, cur);
                if (s == null) break;
                chain.insert (0, s);
                cur = s.based_on;
            }
            var r = new CellStyle (name);
            foreach (var s in chain) {
                if (s.fill != "") r.fill = s.fill;
                if (s.valign >= 0) r.valign = s.valign;
                if (s.diagonal >= 0) r.diagonal = s.diagonal;
                if (s.para_style != "") r.para_style = s.para_style;
            }
            return r;
        }

        public static string region_style (Publication pub, TableItem t, int row, int col) {
            if (t.table_style == "") return "";
            var ts = resolve_table (pub, t.table_style);
            if (row < t.header_rows && ts.header_cell != "") return ts.header_cell;
            if (col == 0 && ts.first_col_cell != "") return ts.first_col_cell;
            return ts.body_cell;
        }

        public static CellStyle? effective_cell (Publication pub, TableItem t, int row, int col) {
            var cell = t.cells[row][col];
            string name = cell.cell_style != "" ? cell.cell_style : region_style (pub, t, row, col);
            if (name == "" || find_cell (pub, name) == null) return null;
            return resolve_cell (pub, name);
        }

        public static void apply_table (Publication pub, TableItem t, string style_name) {
            string name = style_name.dup ();
            t.table_style = name;
            if (name == "") return;
            var ts = resolve_table (pub, name);
            if (ts.border_color != "") t.border_color = ts.border_color;
            if (ts.border_width >= 0) t.border_width = ts.border_width;
            if (ts.header_fill != "") t.header_fill = ts.header_fill;
            if (ts.alt_fill != "") t.alt_fill = ts.alt_fill;
            if (ts.cell_inset >= 0) t.cell_inset = ts.cell_inset;
            if (ts.repeat_header >= 0) t.repeat_header = ts.repeat_header == 1;
            for (int r = 0; r < t.rows; r++) for (int c = 0; c < t.cols; c++) {
                var cell = t.cells[r][c];
                if (cell.cell_style != "") continue;
                var cs = effective_cell (pub, t, r, c);
                if (cs != null) apply_para (pub, cell, cs);
            }
        }

        public static void apply_cell (Publication pub, Cell cell, string style_name) {
            string name = style_name.dup ();
            cell.cell_style = name;
            if (name == "") return;
            apply_para (pub, cell, resolve_cell (pub, name));
        }

        private static void apply_para (Publication pub, Cell cell, CellStyle cs) {
            if (cs.para_style == "" || pub.styles.find_paragraph (cs.para_style) == null) return;
            foreach (var p in cell.story.paras) p.style = cs.para_style;
        }

        public static int update_all (Publication pub) {
            int n = 0;
            pub.walk ((r) => {
                var t = r.item as TableItem;
                if (t == null) return true;
                if (t.table_style != "") {
                    apply_table (pub, t, t.table_style);
                    n++;
                }
                foreach (var row in t.cells) foreach (var c in row) if (c.cell_style != "") apply_cell (pub, c, c.cell_style);
                return true;
            });
            return n;
        }

        public static TableStyle from_table (string name, TableItem t) {
            var s = new TableStyle (name);
            s.border_color = t.border_color;
            s.border_width = t.border_width;
            s.header_fill = t.header_fill;
            s.alt_fill = t.alt_fill;
            s.cell_inset = t.cell_inset;
            s.repeat_header = t.repeat_header ? 1 : 0;
            return s;
        }
    }
}
