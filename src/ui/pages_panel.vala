using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class PagesPanel : AppSidebar {
        private PublishWindow win;
        private BubbleSwitcher switcher;
        private Box pages_box;
        private Box masters_box;
        private Stack stack;
        private Gee.ArrayList<Picture> page_pics = new Gee.ArrayList<Picture> ();
        private Gee.ArrayList<Widget> page_cells = new Gee.ArrayList<Widget> ();
        private bool masters = false;

        public PagesPanel (PublishWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            sidebar_width = 208;
            this.win = win;
            switcher = new BubbleSwitcher ();
            switcher.add_option ("pages", _("Pages"));
            switcher.add_option ("masters", _("Masters"));
            switcher.set_active ("pages");
            switcher.selected.connect ((name) => {
                if (win.doc == null) return;
                bool m = name == "masters";
                if (m != win.canvas.master_mode) win.set_master_mode (m);
            });
            add_bubble_widget (switcher);
            var add = add_bubble_icon ("list-add-symbolic", _("Add Page (Ctrl+Shift+P)"), () => {
                if (masters) win.new_master ();
                else win.run ("add-page");
            });
            add.tooltip_text = _("Add");
            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            pages_box = new Box (Orientation.VERTICAL, 6);
            masters_box = new Box (Orientation.VERTICAL, 6);
            stack.add_named (pages_box, "pages");
            stack.add_named (masters_box, "masters");
            box.append (stack);
        }

        private Publication pub {
            get { return win.doc.pub; }
        }

        public void show_masters (bool on) {
            masters = on;
            switcher.set_active (on ? "masters" : "pages");
            stack.visible_child_name = on ? "masters" : "pages";
            load ();
        }

        private Picture thumb (int page, int size) {
            var pic = new Picture ();
            pic.can_shrink = true;
            pic.content_fit = ContentFit.CONTAIN;
            double w = pub.page_w (page), h = pub.page_h (page);
            double sc = double.min (size / w, size / h);
            pic.set_size_request ((int) (w * sc), (int) (h * sc));
            pic.add_css_class ("publish-page-thumb");
            pic.paintable = render_thumb (page, null, false, size);
            return pic;
        }

        public Gdk.Paintable render_thumb (int page, MasterPage? m, bool left, int size) {
            double w = m == null ? pub.page_w (page) : pub.settings.width, h = m == null ? pub.page_h (page) : pub.settings.height;
            int scale = 2;
            double sc = double.min (size / w, size / h) * scale;
            int pw = int.max (1, (int) (w * sc)), ph = int.max (1, (int) (h * sc));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            var r = new Renderer (pub, win.canvas.cache);
            r.opts.overset_marks = false;
            r.opts.placeholders = false;
            if (m != null) r.draw_master (cr, m, left);
            else r.draw_page (cr, page, true);
            surf.flush ();
            var pb = Exporter.surface_to_pixbuf (surf, false);
            return Gdk.Texture.for_pixbuf (pb);
        }

        public void load () {
            clear (pages_box);
            clear (masters_box);
            page_pics.clear ();
            page_cells.clear ();
            if (win.doc == null) return;
            if (masters) load_masters ();
            else load_pages ();
        }

        private static void clear (Box b) {
            Widget? c;
            while ((c = b.get_first_child ()) != null) b.remove (c);
        }

        private void load_pages () {
            var spreads = pub.spreads ();
            foreach (var sp in spreads) {
                var row = new Box (Orientation.HORIZONTAL, 2);
                row.halign = Align.CENTER;
                if (pub.settings.facing && !sp.first_is_left) {
                    var spacer = new Box (Orientation.VERTICAL, 0);
                    spacer.set_size_request (84, -1);
                    row.append (spacer);
                }
                foreach (int p in sp.pages) row.append (page_cell (p));
                if (pub.settings.facing && sp.pages.size == 1 && sp.first_is_left) {
                    var spacer = new Box (Orientation.VERTICAL, 0);
                    spacer.set_size_request (84, -1);
                    row.append (spacer);
                }
                pages_box.append (row);
            }
            select_page (win.doc.current_page);
        }

        private Widget page_cell (int p) {
            int size = pub.settings.facing ? 78 : 120;
            var b = new Button ();
            b.add_css_class ("flat");
            b.add_css_class ("publish-page-cell");
            var v = new Box (Orientation.VERTICAL, 4);
            var pic = thumb (p, size);
            v.append (pic);
            var pg = pub.pages[p];
            var sec = pub.section_starting (p);
            string label = pub.page_label (p);
            if (pg.master != "") label = "%s  %s".printf (label, pg.master);
            var l = new Label (label);
            l.add_css_class ("publish-page-label");
            if (sec != null && p > 0) l.add_css_class ("accent");
            v.append (l);
            b.child = v;
            b.tooltip_text = sec != null && sec.name != "" ? _("Page %s, section %s").printf (pub.page_label (p), sec.name) : _("Page %s").printf (pub.page_label (p));
            b.clicked.connect (() => win.go_to_page (p));
            var click = new GestureClick ();
            click.button = Gdk.BUTTON_SECONDARY;
            click.pressed.connect ((n, x, y) => page_menu (b, p, x, y));
            b.add_controller (click);
            var drag = new DragSource ();
            drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect ((x, y) => new Gdk.ContentProvider.for_value (p));
            b.add_controller (drag);
            var drop = new DropTarget (typeof (int), Gdk.DragAction.MOVE);
            drop.drop.connect ((val, x, y) => {
                int from = val.get_int ();
                if (from != p) win.move_page (from, p);
                return true;
            });
            b.add_controller (drop);
            page_pics.add (pic);
            page_cells.add (b);
            return b;
        }

        private void page_menu (Widget anchor, int p, double x, double y) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Insert Page Before"), "document-new-symbolic", () => win.add_pages (p, 1, null));
            menu.add_item (_("Insert Page After"), "document-new-symbolic", () => win.add_pages (p + 1, 1, null));
            menu.add_item (_("Duplicate Page"), "edit-copy-symbolic", () => win.duplicate_page (p));
            var apply = menu.add_submenu (_("Apply Master"), null);
            apply.add_item (_("None"), null, () => win.apply_master (p, ""));
            foreach (var m in pub.masters) {
                string id = m.id;
                apply.add_item (m.display_name (), null, () => win.apply_master (p, id));
            }
            menu.add_item (_("Numbering and Section Options…"), null, () => Dialogs.sections (win, p));
            menu.add_item (pub.pages[p].hide_master ? _("Show Master Items") : _("Hide Master Items"), null, () => {
                bool v = !pub.pages[p].hide_master;
                win.edit (_("Master Items"), () => pub.pages[p].hide_master = v);
                load ();
            });
            menu.add_separator ();
            menu.add_item (_("Delete Page"), "user-trash-symbolic", () => win.delete_page (p), "destructive-action");
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = 1;
            r.height = 1;
            menu.pointing_to = r;
            PublishWindow.popup_menu (menu);
        }

        public void select_page (int p) {
            for (int i = 0; i < page_cells.size; i++) {
                if (i == p) page_cells[i].add_css_class ("current");
                else page_cells[i].remove_css_class ("current");
            }
        }

        public void refresh_current () {
            if (win.doc == null) return;
            if (masters) {
                load ();
                return;
            }
            int p = win.doc.current_page;
            if (p >= 0 && p < page_pics.size) page_pics[p].paintable = render_thumb (p, null, false, pub.settings.facing ? 78 : 120);
        }

        private void load_masters () {
            foreach (var m in pub.masters) {
                var mm = m;
                var b = new Button ();
                b.add_css_class ("flat");
                b.add_css_class ("publish-page-cell");
                if (win.canvas.master_mode && win.canvas.master_id == m.id) b.add_css_class ("current");
                var v = new Box (Orientation.VERTICAL, 4);
                var row = new Box (Orientation.HORIZONTAL, 2);
                row.halign = Align.CENTER;
                int size = pub.settings.facing ? 78 : 120;
                if (pub.settings.facing) {
                    var lp = new Picture ();
                    lp.paintable = render_thumb (-1, m, true, size);
                    lp.add_css_class ("publish-page-thumb");
                    row.append (lp);
                }
                var rp = new Picture ();
                rp.paintable = render_thumb (-1, m, false, size);
                rp.add_css_class ("publish-page-thumb");
                row.append (rp);
                v.append (row);
                var l = new Label (m.display_name () + (m.based_on != "" ? " (" + _("based on %s").printf (m.based_on) + ")" : ""));
                l.add_css_class ("publish-page-label");
                l.ellipsize = Pango.EllipsizeMode.END;
                v.append (l);
                b.child = v;
                b.clicked.connect (() => win.set_master_mode (true, mm.id));
                var click = new GestureClick ();
                click.button = Gdk.BUTTON_SECONDARY;
                click.pressed.connect ((n, x, y) => master_menu (b, mm, x, y));
                b.add_controller (click);
                masters_box.append (b);
            }
        }

        private void master_menu (Widget anchor, MasterPage m, double x, double y) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Rename…"), "document-edit-symbolic", () => Dialogs.rename_master (win, m));
            menu.add_item (_("Duplicate Master"), "edit-copy-symbolic", () => {
                string id = pub.next_master_id ();
                win.edit (_("Duplicate Master"), () => {
                    var c = m.clone ();
                    c.id = id;
                    c.name = m.name;
                    foreach (var it in c.items) pub.reassign (it);
                    foreach (var it in c.left_items) pub.reassign (it);
                    pub.masters.add (c);
                });
                load ();
            });
            var based = menu.add_submenu (_("Based On"), null);
            based.add_item (_("None"), null, () => {
                win.edit (_("Based On"), () => m.based_on = "");
                load ();
            });
            foreach (var o in pub.masters) {
                if (o == m) continue;
                string oid = o.id;
                based.add_item (o.display_name (), null, () => {
                    string chain_check = oid;
                    bool cycle = false;
                    foreach (var c in pub.master_chain (chain_check)) if (c == m) cycle = true;
                    if (cycle) {
                        win.toast (_("A master cannot be based on itself"));
                        return;
                    }
                    win.edit (_("Based On"), () => m.based_on = oid);
                    load ();
                });
            }
            menu.add_item (_("Apply to All Pages"), null, () => {
                win.edit (_("Apply Master"), () => {
                    foreach (var p in pub.pages) p.master = m.id;
                });
                load ();
            });
            menu.add_separator ();
            menu.add_item (_("Delete Master"), "user-trash-symbolic", () => {
                if (pub.masters.size <= 1) {
                    win.toast (_("A publication keeps at least one master page"));
                    return;
                }
                win.edit (_("Delete Master"), () => {
                    pub.masters.remove (m);
                    foreach (var p in pub.pages) if (p.master == m.id) p.master = pub.masters[0].id;
                    foreach (var o in pub.masters) if (o.based_on == m.id) o.based_on = "";
                    pub.prune_stories ();
                });
                win.set_master_mode (true, pub.masters[0].id);
            }, "destructive-action");
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = 1;
            r.height = 1;
            menu.pointing_to = r;
            PublishWindow.popup_menu (menu);
        }
    }
}
