namespace Singularity.Apps.Publish {

    public class LinkedTables {
        public static Gee.ArrayList<Gee.ArrayList<string>> load (Publication pub, TableItem t) throws Error {
            string path = ImageStore.resolve_link (pub, t.link_path);
            uint8[] data;
            FileUtils.get_data (path, out data);
            var rows = SheetReader.read_rows (data, t.link_sheet);
            var trimmed = new Gee.ArrayList<Gee.ArrayList<string>> ();
            foreach (var r in rows) {
                bool any = false;
                foreach (string v in r) if (v.strip () != "") any = true;
                if (any) trimmed.add (r);
            }
            return trimmed;
        }

        public static TableItem create (Publication pub, string path, int sheet, double x, double y, double width) throws Error {
            var t = new TableItem (1, 1);
            t.id = pub.next_id ();
            t.link_path = path;
            t.link_sheet = sheet;
            var rows = load (pub, t);
            int cols = 1;
            foreach (var r in rows) cols = int.max (cols, r.size);
            t.rows = int.max (1, rows.size);
            t.cols = cols;
            t.x = x;
            t.y = y;
            t.w = width;
            t.h = 18 * t.rows;
            t.init_cells (pub);
            fill (t, rows);
            t.link_stamp = ImageStore.stamp_for (ImageStore.resolve_link (pub, path));
            return t;
        }

        private static void fill (TableItem t, Gee.List<Gee.ArrayList<string>> rows) {
            for (int r = 0; r < t.rows; r++) for (int c = 0; c < t.cols; c++) {
                string v = r < rows.size && c < rows[r].size ? rows[r][c] : "";
                var st = t.cells[r][c].story;
                if (st.paras.size == 0) st.paras.add (new Paragraph.with_text (""));
                var p = st.paras[0];
                while (st.paras.size > 1) st.paras.remove_at (st.paras.size - 1);
                if (p.runs.size == 0) p.runs.add (new Run (""));
                var keep = p.runs[0];
                p.runs.clear ();
                keep.text = v;
                keep.field = "";
                p.runs.add (keep);
            }
        }

        public static bool modified (Publication pub, TableItem t) {
            if (t.link_path == "") return false;
            string path = ImageStore.resolve_link (pub, t.link_path);
            if (!FileUtils.test (path, FileTest.IS_REGULAR)) return false;
            return ImageStore.stamp_for (path) != t.link_stamp;
        }

        public static bool missing (Publication pub, TableItem t) {
            return t.link_path != "" && !FileUtils.test (ImageStore.resolve_link (pub, t.link_path), FileTest.IS_REGULAR);
        }

        public static void update (Publication pub, TableItem t) throws Error {
            var rows = load (pub, t);
            int cols = 1;
            foreach (var r in rows) cols = int.max (cols, r.size);
            int nr = int.max (1, rows.size);
            while (t.rows < nr) {
                var row = new Gee.ArrayList<Cell> ();
                for (int c = 0; c < t.cols; c++) {
                    var cell = new Cell (pub.next_id ());
                    if (t.rows > 0) {
                        var above = t.cells[t.rows - 1][c];
                        cell.fill = above.fill;
                        cell.valign = above.valign;
                        cell.cell_style = above.cell_style;
                        cell.story.paras[0].style = above.story.paras.size > 0 ? above.story.paras[0].style : StyleSheet.BASIC;
                    }
                    row.add (cell);
                }
                t.cells.add (row);
                t.row_h.add (t.row_h.size > 0 ? t.row_h[t.row_h.size - 1] : 18);
                t.rows++;
            }
            while (t.rows > nr) {
                t.cells.remove_at (t.rows - 1);
                t.row_h.remove_at (t.rows - 1);
                t.rows--;
            }
            while (t.cols < cols) {
                foreach (var row in t.cells) {
                    var cell = new Cell (pub.next_id ());
                    row.add (cell);
                }
                t.col_w.add (t.col_w.size > 0 ? t.col_w[t.col_w.size - 1] : 60);
                t.cols++;
            }
            while (t.cols > cols) {
                foreach (var row in t.cells) row.remove_at (t.cols - 1);
                t.col_w.remove_at (t.cols - 1);
                t.cols--;
            }
            foreach (var row in t.cells) foreach (var c in row) {
                c.covered = false;
                c.row_span = 1;
                c.col_span = 1;
            }
            fill (t, rows);
            double h = 0, w = 0;
            foreach (var v in t.row_h) h += v;
            foreach (var v in t.col_w) w += v;
            t.h = h;
            t.w = w;
            t.link_stamp = ImageStore.stamp_for (ImageStore.resolve_link (pub, t.link_path));
        }

        public static int update_all (Publication pub, bool only_modified = true) {
            int n = 0;
            pub.walk ((r) => {
                var t = r.item as TableItem;
                if (t == null || t.link_path == "" || (only_modified && !modified (pub, t))) return true;
                try {
                    update (pub, t);
                    n++;
                } catch (Error e) {
                }
                return true;
            });
            return n;
        }
    }
}
