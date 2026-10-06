using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class ProActions {
        private static Gee.ArrayList<ImageFrame> images (PublishWindow w) {
            var l = new Gee.ArrayList<ImageFrame> ();
            foreach (var it in w.sel ()) if (it is ImageFrame) l.add ((ImageFrame) it);
            return l;
        }

        private static TableItem? table (PublishWindow w) {
            if (w.canvas.edit != null && w.canvas.edit.table != null) return w.canvas.edit.table;
            if (w.sel ().size == 1 && w.sel ()[0] is TableItem) return (TableItem) w.sel ()[0];
            return null;
        }

        public static void install (PublishWindow w) {
            TypographyDialogs.install (w);
            BookDialog.install (w);
            ReviewPanel.install (w);
            w.doc_action ("export-story", () => {
                TextFrame? tf = null;
                foreach (var it in w.sel ()) if (it is TextFrame) tf = (TextFrame) it;
                if (tf == null && w.canvas.edit != null) tf = w.canvas.edit.frame;
                if (tf == null) {
                    w.toast (_("Select a text frame first"));
                    return;
                }
                var frame = tf;
                w.ask_save.begin (_("Export Story for Writing"), w.base_name (_("Story")) + "." + LinkedStory.EXT, { LinkedStory.EXT }, _("Publish Story"), (o, res) => {
                    var file = w.ask_save.end (res);
                    if (file == null) return;
                    try {
                        var st = w.doc.pub.story (frame.story);
                        w.edit (_("Link Story"), () => {
                            try {
                                LinkedStory.export (w.doc.pub, st, file.get_path ());
                            } catch (Error e) {
                            }
                        });
                        if (st.link_path == "") throw new FileError.FAILED (_("The file could not be written"));
                        w.toast (_("Writers can now open \"%s\" in Publish and edit only the text").printf (file.get_basename ()));
                    } catch (Error e) {
                        w.show_error (_("Could Not Export the Story"), e.message);
                    }
                });
            });
            string[] ops = { "unite", "subtract", "intersect", "exclude" };
            Singularity.Vector.BoolOp[] kinds = { Singularity.Vector.BoolOp.UNION, Singularity.Vector.BoolOp.SUBTRACT, Singularity.Vector.BoolOp.INTERSECT, Singularity.Vector.BoolOp.EXCLUDE };
            for (int i = 0; i < ops.length; i++) {
                var op = kinds[i];
                w.doc_action ("pathfinder-" + ops[i], () => {
                    var items = new Gee.ArrayList<Item> ();
                    items.add_all (w.sel ());
                    if (items.size < 2) {
                        w.toast (_("Select two or more shapes"));
                        return;
                    }
                    var list = w.canvas.active_list ();
                    items.sort ((a, b) => list.index_of (a) - list.index_of (b));
                    var made = Pathfinder.combine (w.doc.pub, items, op);
                    if (made == null) {
                        w.toast (_("These objects cannot be combined"));
                        return;
                    }
                    w.edit (_("Pathfinder"), () => {
                        int at = list.index_of (items[items.size - 1]);
                        foreach (var it in items) list.remove (it);
                        list.insert (int.min (int.max (0, at - items.size + 1), list.size), made);
                    });
                    w.canvas.select_only (made);
                });
            }
            w.doc_action ("convert-to-path", () => {
                var items = new Gee.ArrayList<Item> ();
                items.add_all (w.sel ());
                var list = w.canvas.active_list ();
                var made = new Gee.ArrayList<Item> ();
                w.edit (_("Convert to Path"), () => {
                    foreach (var it in items) {
                        var p = Pathfinder.convert_to_path (w.doc.pub, it);
                        if (p == null || it is TextFrame || it is ImageFrame) continue;
                        int at = list.index_of (it);
                        if (at < 0) continue;
                        list[at] = p;
                        made.add (p);
                    }
                });
                if (made.size > 0) w.canvas.select_only (made[0]);
            });
            w.doc_action ("export-html", () => ProDialogs.export_web.begin (w));
            w.doc_action ("export-epub", () => ProDialogs.export_epub.begin (w, false));
            w.doc_action ("export-epub-fixed", () => ProDialogs.export_epub.begin (w, true));
            w.doc_action ("export-site", () => ProDialogs.export_site.begin (w));
            w.doc_action ("export-xps", () => ProDialogs.export_xps.begin (w));
            w.doc_action ("export-docx", () => ProDialogs.export_docx.begin (w));
            w.doc_action ("export-odg", () => ProDialogs.export_odg.begin (w));
            w.doc_action ("export-idml", () => ProDialogs.export_idml.begin (w));
            w.doc_action ("send-email", () => ProDialogs.send_email (w));
            w.doc_action ("insert-building-block", () => ProDialogs.building_blocks (w));
            w.doc_action ("save-building-block", () => ProDialogs.save_block (w));
            w.doc_action ("insert-wordart", () => ProDialogs.wordart (w, null));
            w.doc_param_action ("insert-preset", (id) => insert_preset (w, id));
            w.doc_action ("insert-text-file", () => ProDialogs.insert_text_file.begin (w));
            w.doc_action ("import-styles", () => ProDialogs.import_styles.begin (w));
            w.doc_action ("insert-symbol", () => SymbolDialog.open (w));
            w.doc_action ("insert-hyperlink", () => ProDialogs.hyperlink (w));
            w.doc_action ("remove-hyperlink", () => remove_link (w));
            w.doc_action ("insert-bookmark", () => ProDialogs.bookmark (w));
            w.doc_action ("bookmarks", () => ProDialogs.bookmarks (w));
            w.doc_param_action ("insert-business-field", (k) => w.insert_field_or_frame (Fields.biz (k)));
            w.doc_action ("insert-time", () => w.insert_field_or_frame (Fields.TIME));
            w.doc_action ("business-information", () => ProDialogs.business (w));
            w.doc_action ("color-schemes", () => ProDialogs.color_schemes (w));
            w.doc_action ("font-schemes", () => ProDialogs.font_schemes (w));
            w.doc_param_action ("picture-style", (id) => {
                var ims = images (w);
                if (ims.size == 0) return;
                w.edit (_("Picture Style"), () => {
                    foreach (var im in ims) PictureStyles.apply (im, id);
                });
                w.inspector.rebuild ();
            });
            w.doc_param_action ("crop-to-shape", (id) => {
                var ims = images (w);
                if (ims.size == 0) return;
                w.edit (_("Crop to Shape"), () => {
                    foreach (var im in ims) im.clip_shape = id;
                });
                w.inspector.rebuild ();
            });
            w.doc_action ("reset-picture", () => {
                var ims = images (w);
                if (ims.size == 0) return;
                w.edit (_("Reset Picture"), () => {
                    foreach (var im in ims) {
                        PictureStyles.apply (im, "");
                        im.brightness = 0;
                        im.contrast = 0;
                        im.recolor = 0;
                        im.transparent_color = "";
                        im.rotation = 0;
                    }
                });
                w.inspector.rebuild ();
            });
            w.doc_param_action ("add-caption", (style) => {
                var im = w.single_image ();
                if (im == null) {
                    w.toast (_("Select a picture first"));
                    return;
                }
                GroupItem? g = null;
                w.edit (_("Add Caption"), () => g = Captions.add (w.doc.pub, w.canvas.active_list (), im, style, im.alt_text));
                if (g != null) w.canvas.select_only (g);
            });
            w.doc_action ("swap-pictures", () => {
                var ims = images (w);
                if (ims.size != 2) {
                    w.toast (_("Select exactly two pictures to swap"));
                    return;
                }
                w.edit (_("Swap Pictures"), () => PictureStyles.swap (ims[0], ims[1]));
                w.links_panel.rebuild ();
            });
            w.doc_action ("alt-text", () => ProDialogs.alt_text (w));
            w.doc_param_action ("table-format", (id) => {
                var t = table (w);
                if (t == null) return;
                w.canvas.end_edit ();
                w.edit (_("Table Format"), () => TableFormats.apply (w.doc.pub, t, id));
                w.canvas.select_only (t);
            });
            w.doc_param_action ("cell-diagonal", (v) => {
                var t = table (w);
                if (t == null) return;
                int r1 = w.canvas.cell_r1 >= 0 ? int.min (w.canvas.cell_r1, w.canvas.cell_r2) : 0, r2 = w.canvas.cell_r1 >= 0 ? int.max (w.canvas.cell_r1, w.canvas.cell_r2) : t.rows - 1;
                int c1 = w.canvas.cell_c1 >= 0 ? int.min (w.canvas.cell_c1, w.canvas.cell_c2) : 0, c2 = w.canvas.cell_c1 >= 0 ? int.max (w.canvas.cell_c1, w.canvas.cell_c2) : t.cols - 1;
                int d = int.parse (v);
                w.edit (_("Diagonal"), () => {
                    for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) t.cells[r][c].diagonal = d;
                });
            });
            w.doc_param_action ("autofit", (v) => {
                var t = w.single_text_frame ();
                if (t == null) return;
                w.edit (_("Text Fit"), () => {
                    if (v == "grow") {
                        t.autofit = 0;
                        t.auto_height = true;
                    } else {
                        t.autofit = int.parse (v).clamp (0, 2);
                        t.auto_height = false;
                    }
                });
                w.canvas.invalidate ();
                w.inspector.rebuild ();
            });
            w.doc_action ("autoflow", () => autoflow (w));
            w.doc_action ("text-direction", () => {
                var t = w.single_text_frame ();
                if (t == null) return;
                w.edit (_("Text Direction"), () => t.vertical = !t.vertical);
                w.canvas.invalidate ();
            });
            w.doc_action ("edit-wrap-points", () => {
                if (w.canvas.wrap_item != null) {
                    w.canvas.stop_wrap_edit ();
                    w.inspector.rebuild ();
                    return;
                }
                if (w.sel ().size != 1) {
                    w.toast (_("Select one object to edit its wrap points"));
                    return;
                }
                var it = w.sel ()[0];
                w.edit (_("Edit Wrap Points"), () => w.canvas.start_wrap_edit (it));
                w.toast (_("Drag the points, click an edge to add one, Alt-click a point to remove it"));
                w.inspector.rebuild ();
            });
            w.doc_action ("reset-wrap-points", () => {
                if (w.sel ().size == 0) return;
                var items = new Gee.ArrayList<Item> ();
                items.add_all (w.sel ());
                w.canvas.stop_wrap_edit ();
                w.edit (_("Reset Wrap Points"), () => {
                    foreach (var it in items) it.wrap_points.clear ();
                });
                w.canvas.invalidate ();
                w.inspector.rebuild ();
            });
            w.doc_action ("border-art", () => ProDialogs.border_art (w));
            w.doc_action ("design-checker", () => {
                w.preflight_panel.mode = 0;
                w.toggle_panel ("preflight", true);
            });
            w.doc_action ("accessibility-checker", () => {
                w.preflight_panel.mode = 2;
                w.toggle_panel ("preflight", true);
            });
            w.doc_action ("commercial-checker", () => {
                w.preflight_panel.mode = 1;
                w.toggle_panel ("preflight", true);
            });
            w.doc_action ("macros", () => MacrosUi.manager (w));
            w.doc_action ("macro-record", () => MacrosUi.toggle_record (w));
            w.doc_action ("thesaurus", () => ProDialogs.thesaurus (w));
            w.doc_action ("find-advanced", () => FindDialog.open (w));
            w.doc_action ("merge-sheet", () => ProDialogs.merge_sheet.begin (w));
            w.doc_action ("place-spreadsheet", () => ProDialogs.place_spreadsheet.begin (w));
            w.doc_action ("import-xml", () => ProDialogs.import_xml.begin (w));
            w.doc_action ("update-alternate-layouts", () => {
                int n = 0;
                w.edit (_("Update Alternate Layouts"), () => n = AlternateLayouts.update (w.doc.pub));
                w.canvas.invalidate ();
                w.toast (ngettext ("Updated %d story", "Updated %d stories", n).printf (n));
            });
            w.doc_action ("alternate-layout", () => {
                var pub = w.doc.pub;
                var dlg = Dialogs.make (w, _("Create Alternate Layout"), 460, 460);
                var box = Dialogs.body (dlg);
                var g = new PreferencesGroup (_("New Layout"), _("A copy of the pages at another size; objects follow their liquid layout rules and the text stays linked to the original"));
                var src_names = AlternateLayouts.names (pub);
                string[] labels = {};
                foreach (string n in src_names) labels += n != "" ? n : _("Original");
                var src = new SelectionRow (_("From"), labels, labels[0]);
                g.add_row (src);
                var name = new EntryRow (_("Name"));
                name.text = _("Landscape");
                g.add_row (name);
                string unit = pub.settings.units;
                var wr = new SpinRow (_("Width (%s)").printf (Units.label (unit)), null, 1, 5000, 1, Math.round (Units.to_unit (pub.settings.height, unit)));
                g.add_row (wr);
                var hr = new SpinRow (_("Height (%s)").printf (Units.label (unit)), null, 1, 5000, 1, Math.round (Units.to_unit (pub.settings.width, unit)));
                g.add_row (hr);
                box.append (g);
                Dialogs.footer (dlg, _("Create"), () => {
                    string from = src_names[0];
                    for (int i = 0; i < labels.length; i++) if (labels[i] == src.current_value) from = src_names[i];
                    int first = -1;
                    string nm = name.text.strip () != "" ? name.text.strip () : _("Alternate");
                    w.edit (_("Create Alternate Layout"), () => first = AlternateLayouts.create (pub, from, nm, Units.from_unit (wr.spin_btn.value, unit), Units.from_unit (hr.spin_btn.value, unit)));
                    w.canvas.relayout ();
                    w.pages_panel.load ();
                    if (first >= 0) w.go_to_page (first);
                });
                dlg.open_dialog ();
            });
            w.doc_action ("merge-database", () => ProDialogs.merge_database.begin (w));
            w.doc_action ("merge-new-list", () => RecipientsDialog.new_list (w));
            w.doc_action ("merge-recipients", () => RecipientsDialog.open (w));
            w.doc_action ("merge-email", () => ProDialogs.merge_email.begin (w));
            w.doc_action ("convert-rgb-swatches", () => {
                var cm = ColorManager.for_settings (w.doc.pub.settings);
                int n = 0;
                w.edit (_("Convert Swatches to CMYK"), () => {
                    foreach (var sw in w.doc.pub.swatches) {
                        if (sw.model != ColorModel.RGB) continue;
                        cm.rgb_to_cmyk (sw.r, sw.g, sw.b, out sw.c, out sw.m, out sw.y, out sw.k);
                        sw.model = ColorModel.CMYK;
                        n++;
                    }
                });
                w.swatches_panel.rebuild ();
                w.toast (ngettext ("Converted %d swatch with %s", "Converted %d swatches with %s", n).printf (n, cm.description ()));
            });
            w.doc_action ("tool-freeform", () => w.canvas.set_tool (Tool.FREEFORM));
            w.doc_action ("tool-pen", () => w.canvas.set_tool (Tool.PEN));
            var app = w.app;
            app.set_accels_for_action ("win.insert-hyperlink", { "<Control>k" });
            app.set_accels_for_action ("win.thesaurus", { "<Shift>F7" });
            app.set_accels_for_action ("win.spelling", { "F7", "<Control>i" });
            app.set_accels_for_action ("win.insert-building-block", { "<Control><Alt>k" });
            app.set_accels_for_action ("win.accessibility-checker", { "<Control><Alt><Shift>a" });
        }

        public static void insert_preset (PublishWindow w, string id) {
            var r = w.default_frame_rect (140, 120);
            var s = ShapeLib.make (w.doc.pub, id, r.x, r.y, r.w, r.h);
            w.add_item (s, _("Insert Shape"));
        }

        public static void remove_link (PublishWindow w) {
            if (w.canvas.edit != null) {
                w.format_runs (_("Remove Hyperlink"), (r) => {
                    r.fmt.link = "";
                    if (r.cstyle == StyleSheet.HYPERLINK) r.cstyle = "";
                });
                return;
            }
            var items = new Gee.ArrayList<Item> ();
            items.add_all (w.sel ());
            w.edit (_("Remove Hyperlink"), () => {
                foreach (var it in items) it.link = "";
            });
        }

        public static void autoflow (PublishWindow w) {
            var t = w.single_text_frame ();
            if (t == null) {
                w.toast (_("Select the text frame whose story does not fit"));
                return;
            }
            int sid = t.story;
            w.canvas.end_edit ();
            int added = 0;
            w.edit (_("Autoflow"), () => added = Autoflow.run (w.doc.pub, sid));
            w.canvas.relayout ();
            w.canvas.queue_allocate ();
            w.canvas.invalidate ();
            w.pages_panel.load ();
            w.toast (added > 0 ? ngettext ("Added %d page to fit the story", "Added %d pages to fit the story", added).printf (added) : _("The story already fits"));
        }
    }
}
