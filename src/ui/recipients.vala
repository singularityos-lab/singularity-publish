using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class RecipientsDialog {
        private class FilterRow {
            public SelectionRow field;
            public SelectionRow op;
            public EntryRow value;
            public SelectionRow join;
        }

        public static void open (PublishWindow w) {
            var pub = w.doc.pub;
            var ms = pub.merge;
            if (!ms.active ()) {
                w.toast (_("Choose a data source first"));
                return;
            }
            var dlg = Dialogs.make (w, _("Edit Recipient List"), 820, 760);
            var box = Dialogs.body (dlg);
            var excluded = new Gee.HashSet<int> ();
            excluded.add_all (ms.excluded);
            string[] fields = ms.fields.to_array ();
            string[] ops = new string[FilterOp.all ().length];
            for (int i = 0; i < ops.length; i++) ops[i] = FilterOp.all ()[i].label ();
            string[] joins = { _("And"), _("Or") };
            var fg = new PreferencesGroup (_("Filter"), _("Only recipients matching every condition are merged"));
            var filter_rows = new Gee.ArrayList<FilterRow> ();
            for (int i = 0; i < 3; i++) {
                var fr = new FilterRow ();
                MergeFilter? existing = i < ms.filters.size ? ms.filters[i] : null;
                if (i > 0) {
                    fr.join = new SelectionRow (_("Combine"), joins, existing != null && existing.or_previous ? joins[1] : joins[0]);
                    fg.add_row (fr.join);
                }
                string[] fchoices = new string[fields.length + 1];
                fchoices[0] = _("None");
                for (int k = 0; k < fields.length; k++) fchoices[k + 1] = fields[k];
                fr.field = new SelectionRow (_("Field %d").printf (i + 1), fchoices, existing != null ? existing.field : fchoices[0]);
                fg.add_row (fr.field);
                fr.op = new SelectionRow (_("Condition"), ops, existing != null ? existing.op.label () : ops[0]);
                fg.add_row (fr.op);
                fr.value = new EntryRow (_("Value"));
                if (existing != null) fr.value.text = existing.value;
                fg.add_row (fr.value);
                filter_rows.add (fr);
            }
            box.append (fg);
            var sg = new PreferencesGroup (_("Sort"));
            string[] schoices = new string[fields.length + 1];
            schoices[0] = _("None");
            for (int k = 0; k < fields.length; k++) schoices[k + 1] = fields[k];
            var sort_fields = new Gee.ArrayList<SelectionRow> ();
            var sort_desc = new Gee.ArrayList<SwitchRow> ();
            for (int i = 0; i < 2; i++) {
                var existing = i < ms.sorts.size ? ms.sorts[i] : null;
                var sf = new SelectionRow (i == 0 ? _("Sort By") : _("Then By"), schoices, existing != null ? existing.field : schoices[0]);
                sg.add_row (sf);
                var sd = new SwitchRow (_("Descending"), null, existing != null && existing.descending);
                sg.add_row (sd);
                sort_fields.add (sf);
                sort_desc.add (sd);
            }
            box.append (sg);
            var lg = new PreferencesGroup (_("Recipients"), _("Clear a check box to leave that recipient out"));
            var search = new EntryRow (_("Find Recipient"));
            lg.add_row (search);
            box.append (lg);
            var list = new ListBox ();
            list.selection_mode = SelectionMode.NONE;
            list.add_css_class ("boxed-list");
            int show = int.min (fields.length, 4);
            var rows = new Gee.ArrayList<ListBoxRow> ();
            for (int r = 0; r < ms.records.size; r++) {
                int rec = r;
                var row = new ListBoxRow ();
                var hb = new Box (Orientation.HORIZONTAL, 12);
                hb.margin_start = hb.margin_end = 10;
                hb.margin_top = hb.margin_bottom = 6;
                var check = new CheckButton ();
                check.active = !excluded.contains (rec);
                check.toggled.connect (() => {
                    if (check.active) excluded.remove (rec);
                    else excluded.add (rec);
                });
                hb.append (check);
                for (int k = 0; k < show; k++) {
                    var l = new Label (ms.value (rec, fields[k]));
                    l.xalign = 0;
                    l.hexpand = true;
                    l.ellipsize = Pango.EllipsizeMode.END;
                    l.width_chars = 12;
                    hb.append (l);
                }
                row.child = hb;
                list.append (row);
                rows.add (row);
            }
            search.entry_changed.connect (() => {
                string q = search.text.strip ().casefold ();
                for (int r = 0; r < rows.size; r++) {
                    bool hit = q == "";
                    if (!hit) foreach (string f in fields) if (ms.value (r, f).casefold ().contains (q)) hit = true;
                    rows[r].visible = hit;
                }
            });
            box.append (list);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            var all = new Button.with_label (_("Include All"));
            all.clicked.connect (() => {
                excluded.clear ();
                dlg.close ();
                ms.excluded.clear ();
                open (w);
            });
            bar.append (all);
            box.append (bar);
            Dialogs.footer (dlg, _("Apply"), () => {
                var filters = new Gee.ArrayList<MergeFilter> ();
                for (int i = 0; i < filter_rows.size; i++) {
                    var fr = filter_rows[i];
                    if (fr.field.current_value == _("None") || fr.field.current_value == "") continue;
                    FilterOp op = FilterOp.EQUALS;
                    foreach (var o in FilterOp.all ()) if (o.label () == fr.op.current_value) op = o;
                    bool or_prev = fr.join != null && fr.join.current_value == joins[1];
                    filters.add (new MergeFilter (fr.field.current_value, op, fr.value.text, or_prev));
                }
                var sorts = new Gee.ArrayList<MergeSort> ();
                for (int i = 0; i < sort_fields.size; i++) {
                    string f = sort_fields[i].current_value;
                    if (f == _("None") || f == "") continue;
                    sorts.add (new MergeSort (f, sort_desc[i].switch_btn.active));
                }
                w.edit (_("Edit Recipient List"), () => {
                    ms.excluded.clear ();
                    ms.excluded.add_all (excluded);
                    ms.filters = filters;
                    ms.sorts = sorts;
                });
                w.merge_panel.rebuild ();
                int n = ms.selected_records ().size;
                w.toast (ngettext ("%d recipient will be merged", "%d recipients will be merged", n).printf (n));
            });
            dlg.open_dialog ();
        }

        public static void new_list (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Type a New List"), 760, 620);
            var box = Dialogs.body (dlg);
            var info = new Label (_("Type the field names in the first row and one recipient per row below."));
            info.xalign = 0;
            info.wrap = true;
            info.add_css_class ("dim-label");
            box.append (info);
            var grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 4;
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.min_content_height = 320;
            scroll.child = grid;
            box.append (scroll);
            var cells = new Gee.ArrayList<Gee.ArrayList<Entry>> ();
            int cols = 0;
            ProDialogs.Done add_col = null;
            ProDialogs.Done add_row = null;
            add_col = () => {
                for (int r = 0; r < cells.size; r++) {
                    var e = new Entry ();
                    e.width_chars = 14;
                    if (r == 0) {
                        e.placeholder_text = _("Field Name");
                        e.add_css_class ("heading");
                    }
                    grid.attach (e, cols, r, 1, 1);
                    cells[r].add (e);
                }
                cols++;
            };
            add_row = () => {
                var row = new Gee.ArrayList<Entry> ();
                int r = cells.size;
                for (int c = 0; c < cols; c++) {
                    var e = new Entry ();
                    e.width_chars = 14;
                    if (r == 0) {
                        e.placeholder_text = _("Field Name");
                        e.add_css_class ("heading");
                    }
                    grid.attach (e, c, r, 1, 1);
                    row.add (e);
                }
                cells.add (row);
            };
            cells.add (new Gee.ArrayList<Entry> ());
            string[] defaults = { _("First Name"), _("Last Name"), _("Email"), _("Address"), _("City") };
            if (pub.merge.active () && pub.merge.source_kind == "list") {
                foreach (string f in pub.merge.fields) {
                    add_col ();
                    cells[0][cols - 1].text = f;
                }
                foreach (var rec in pub.merge.records) {
                    add_row ();
                    for (int c = 0; c < cols && c < rec.size; c++) cells[cells.size - 1][c].text = rec[c];
                }
            } else {
                foreach (string f in defaults) {
                    add_col ();
                    cells[0][cols - 1].text = f;
                }
            }
            for (int i = 0; i < 3; i++) add_row ();
            var bar = new Box (Orientation.HORIZONTAL, 8);
            var br = new Button.with_label (_("Add Recipient"));
            br.clicked.connect (() => add_row ());
            var bc = new Button.with_label (_("Add Field"));
            bc.clicked.connect (() => add_col ());
            bar.append (br);
            bar.append (bc);
            box.append (bar);
            var save_csv = new SwitchRow (_("Also Save as a CSV File"), _("Keep the list for other publications"), false);
            var og = new PreferencesGroup (null);
            og.add_row (save_csv);
            box.append (og);
            Dialogs.footer (dlg, _("Use List"), () => {
                var t = new DataTable ();
                var keep = new Gee.ArrayList<int> ();
                for (int c = 0; c < cols; c++) {
                    string name = cells[0][c].text.strip ();
                    if (name == "") continue;
                    keep.add (c);
                    t.fields.add (name);
                }
                for (int r = 1; r < cells.size; r++) {
                    var rec = new Gee.ArrayList<string> ();
                    bool any = false;
                    foreach (int c in keep) {
                        string v = cells[r][c].text;
                        if (v.strip () != "") any = true;
                        rec.add (v);
                    }
                    if (any) t.records.add (rec);
                }
                if (t.fields.size == 0) return;
                string path = "";
                if (save_csv.switch_btn.active) {
                    var sb = new StringBuilder ();
                    for (int i = 0; i < t.fields.size; i++) {
                        if (i > 0) sb.append (",");
                        sb.append (Csv.escape (t.fields[i]));
                    }
                    sb.append ("\n");
                    foreach (var rec in t.records) {
                        for (int i = 0; i < rec.size; i++) {
                            if (i > 0) sb.append (",");
                            sb.append (Csv.escape (rec[i]));
                        }
                        sb.append ("\n");
                    }
                    path = Path.build_filename (w.default_folder ().get_path (), w.base_name (_("Publication")) + " " + _("Recipients") + ".csv");
                    try {
                        FileUtils.set_contents (path, sb.str);
                    } catch (Error e) {
                        w.show_error (_("Could Not Save the List"), e.message);
                        path = "";
                    }
                }
                w.edit (_("New Recipient List"), () => Merge.set_source (pub, t, path != "" ? "csv" : "list", path));
                w.toggle_panel ("merge", true);
                w.merge_panel.rebuild ();
            });
            dlg.open_dialog ();
        }
    }
}
