namespace Singularity.Apps.Publish {

    public class DbReader {
        public static bool available () {
#if HAVE_SQLITE
            return true;
#else
            return false;
#endif
        }

        public static bool is_read_only_query (string sql) {
            string s = sql.strip ().down ();
            while (s.has_suffix (";")) s = s.substring (0, s.length - 1).strip ();
            if (s.contains (";")) return false;
            if (!s.has_prefix ("select") && !s.has_prefix ("with")) return false;
            foreach (string bad in new string[] { "insert ", "update ", "delete ", "drop ", "alter ", "create ", "attach ", "detach ", "pragma ", "replace ", "vacuum" }) {
                if (s.contains (bad)) return false;
            }
            return true;
        }

#if HAVE_SQLITE
        private static Sqlite.Database open_ro (string path) throws Error {
            if (!FileUtils.test (path, FileTest.IS_REGULAR)) throw new FileError.NOENT (_("The database \"%s\" does not exist.").printf (path));
            Sqlite.Database db;
            int rc = Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READONLY);
            if (rc != Sqlite.OK) throw new FormatError.INVALID (_("The database could not be opened: %s").printf (db != null ? db.errmsg () : rc.to_string ()));
            db.busy_timeout (2000);
            return db;
        }

        private static string cell (Sqlite.Statement st, int i) {
            switch (st.column_type (i)) {
                case Sqlite.NULL:
                    return "";
                case Sqlite.INTEGER:
                    return st.column_int64 (i).to_string ();
                case Sqlite.FLOAT:
                    double v = st.column_double (i);
                    return v == Math.floor (v) && Math.fabs (v) < 1e15 ? "%.0f".printf (v) : "%.10g".printf (v);
                case Sqlite.BLOB:
                    return _("(binary data)");
                default:
                    return st.column_text (i) ?? "";
            }
        }

        private static DataTable run (Sqlite.Database db, string sql) throws Error {
            Sqlite.Statement st;
            int rc = db.prepare_v2 (sql, -1, out st);
            if (rc != Sqlite.OK) throw new FormatError.INVALID (_("The query failed: %s").printf (db.errmsg ()));
            var t = new DataTable ();
            int n = st.column_count ();
            for (int i = 0; i < n; i++) {
                string name = st.column_name (i) ?? _("Field %d").printf (i + 1);
                string unique = name;
                int k = 2;
                while (t.fields.contains (unique)) unique = "%s %d".printf (name, k++);
                t.fields.add (unique);
            }
            int guard = 0;
            while ((rc = st.step ()) == Sqlite.ROW && guard++ < 200000) {
                var rec = new Gee.ArrayList<string> ();
                for (int i = 0; i < n; i++) rec.add (cell (st, i));
                t.records.add (rec);
            }
            if (rc != Sqlite.DONE && rc != Sqlite.ROW) throw new FormatError.INVALID (_("The query failed: %s").printf (db.errmsg ()));
            return t;
        }

        private static string quote_ident (string name) {
            return "\"" + name.replace ("\"", "\"\"") + "\"";
        }
#endif

        public static Gee.ArrayList<string> tables (string path) throws Error {
            var l = new Gee.ArrayList<string> ();
#if HAVE_SQLITE
            var db = open_ro (path);
            var t = run (db, "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name");
            foreach (var rec in t.records) l.add (rec[0]);
#else
            throw new FormatError.UNSUPPORTED (_("This build of Publish was made without SQLite support."));
#endif
            return l;
        }

        public static DataTable read_table (string path, string table) throws Error {
#if HAVE_SQLITE
            var db = open_ro (path);
            bool found = false;
            foreach (string n in tables (path)) if (n == table) found = true;
            if (!found) throw new FormatError.INVALID (_("There is no table named \"%s\".").printf (table));
            return run (db, "SELECT * FROM %s".printf (quote_ident (table)));
#else
            throw new FormatError.UNSUPPORTED (_("This build of Publish was made without SQLite support."));
#endif
        }

        public static DataTable query (string path, string sql) throws Error {
            if (!is_read_only_query (sql)) throw new FormatError.INVALID (_("Only a single SELECT query is allowed."));
#if HAVE_SQLITE
            var db = open_ro (path);
            return run (db, sql);
#else
            throw new FormatError.UNSUPPORTED (_("This build of Publish was made without SQLite support."));
#endif
        }
    }
}
