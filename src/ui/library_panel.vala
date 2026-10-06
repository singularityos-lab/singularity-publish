using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class LibraryPanel : Panel {
        private ulong handler = 0;

        public LibraryPanel (PublishWindow win) {
            base (win);
            handler = Singularity.Assets.AssetLibrary.get_default ().changed.connect (() => {
                if (get_mapped ()) rebuild ();
            });
        }

        public override void rebuild () {
            clear ();
            if (win.doc == null) return;
            var lib = Singularity.Assets.AssetLibrary.get_default ();
            var add = group (_("Add to the Suite Library"), _("Shared with Atelier, Vector, Photos and the other Singularity apps"));
            var ab = new ActionRow (_("Selected Objects as a Block"), _("Logos, signatures and other reusable groups"));
            var abb = new Button.with_label (_("Add"));
            abb.valign = Align.CENTER;
            abb.clicked.connect (() => {
                var items = new Gee.ArrayList<Item> ();
                items.add_all (win.sel ());
                if (items.size == 0) {
                    win.toast (_("Select objects first"));
                    return;
                }
                try {
                    string name = items[0].name != "" ? items[0].name : _("Block %d").printf (lib.list ("block").size + lib.list ("logo").size + 1);
                    lib.add (SuiteAssets.from_items (win.doc.pub, name, items));
                    lib.save ();
                    rebuild ();
                } catch (Error e) {
                    win.show_error (_("Could Not Add to the Library"), e.message);
                }
            });
            ab.add_suffix (abb);
            add.add_row (ab);
            var sw = new ActionRow (_("All Swatches"), _("Every colour of this publication"));
            var swb = new Button.with_label (_("Add"));
            swb.valign = Align.CENTER;
            swb.clicked.connect (() => {
                try {
                    foreach (var s in win.doc.pub.swatches) {
                        if (s.name == "Black" || s.name == "Paper" || s.name == "Registration" || s.tint_of != "") continue;
                        bool exists = false;
                        foreach (var a in lib.list ("color")) if (a.name == s.name) exists = true;
                        if (!exists) lib.add (SuiteAssets.from_swatch (s));
                    }
                    lib.save ();
                    rebuild ();
                } catch (Error e) {
                    win.show_error (_("Could Not Add to the Library"), e.message);
                }
            });
            sw.add_suffix (swb);
            add.add_row (sw);
            var ps = new ActionRow (_("Current Paragraph Style"), null);
            var psb = new Button.with_label (_("Add"));
            psb.valign = Align.CENTER;
            psb.clicked.connect (() => {
                var para = win.current_paragraph ();
                var st = win.doc.pub.styles.find_paragraph (para != null ? para.style : StyleSheet.BASIC);
                if (st == null) return;
                try {
                    lib.add (SuiteAssets.from_paragraph_style (win.doc.pub, st));
                    lib.save ();
                    rebuild ();
                } catch (Error e) {
                    win.show_error (_("Could Not Add to the Library"), e.message);
                }
            });
            ps.add_suffix (psb);
            add.add_row (ps);
            string[] kinds = { "color", "paragraph-style", "block", "logo", "image" };
            string[] titles = { _("Colours"), _("Paragraph Styles"), _("Blocks"), _("Logos"), _("Pictures") };
            for (int k = 0; k < kinds.length; k++) {
                var list = lib.list (kinds[k]);
                if (list.size == 0) continue;
                var g = group (titles[k], ngettext ("%d item", "%d items", list.size).printf (list.size));
                foreach (var asset in list) {
                    var a = asset;
                    string sub = a.app != "" ? _("From %s").printf (a.app) : "";
                    var row = new ActionRow (a.name, sub);
                    if (a.kind == "color") {
                        var dot = new DrawingArea ();
                        dot.set_size_request (18, 18);
                        dot.valign = Align.CENTER;
                        string hex = a.get_field ("color");
                        dot.set_draw_func ((da, cr, w, h) => {
                            var c = Gdk.RGBA ();
                            c.parse (hex);
                            cr.set_source_rgb (c.red, c.green, c.blue);
                            cr.arc (w / 2.0, h / 2.0, 8, 0, 2 * Math.PI);
                            cr.fill ();
                        });
                        row.add_prefix (dot);
                    }
                    var use = icon ("list-add-symbolic", a.kind == "color" ? _("Add to Swatches") : (a.kind == "paragraph-style" ? _("Add to Styles") : _("Place on the Page")));
                    use.clicked.connect (() => use_asset (a));
                    row.add_suffix (use);
                    var del = icon ("user-trash-symbolic", _("Remove from the Library"));
                    del.clicked.connect (() => {
                        try {
                            lib.remove (a.id);
                            lib.save ();
                        } catch (Error e) {
                        }
                        rebuild ();
                    });
                    row.add_suffix (del);
                    g.add_row (row);
                }
            }
        }

        private void use_asset (Singularity.Assets.Asset a) {
            var pub = win.doc.pub;
            switch (a.kind) {
                case "color":
                    var sw = SuiteAssets.to_swatch (a);
                    if (sw == null || pub.swatch (sw.name) != null) {
                        win.toast (_("The swatch is already there"));
                        return;
                    }
                    win.edit (_("Add Swatch"), () => pub.swatches.add (sw));
                    win.toast (_("Added \"%s\" to the swatches").printf (sw.name));
                    break;
                case "paragraph-style":
                    int n = 0;
                    win.edit (_("Add Style"), () => {
                        try {
                            n = SuiteAssets.import_styles (pub, a);
                        } catch (Error e) {
                        }
                    });
                    win.canvas.invalidate ();
                    win.toast (ngettext ("Added %d style", "Added %d styles", n).printf (n));
                    break;
                default:
                    Gee.ArrayList<Item>? made = null;
                    win.edit (_("Place from Library"), () => {
                        try {
                            made = SuiteAssets.place (pub, a, win.canvas.active_list ());
                        } catch (Error e) {
                        }
                    });
                    if (made != null && made.size > 0) win.canvas.select_only (made[0]);
                    win.canvas.invalidate ();
                    break;
            }
        }
    }
}
