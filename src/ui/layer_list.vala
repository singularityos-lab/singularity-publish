using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class LayerList : Box {
        private weak PublishWindow win;
        private ListBox list;
        private Gee.HashSet<int> expanded = new Gee.HashSet<int> ();
        private int current = -1;
        private int editing = -1;
        private ListBoxRow? drop_row = null;
        private Button up_button;
        private Button down_button;
        private Button duplicate_button;
        private Button delete_button;

        public LayerList (PublishWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("sx-layer-list-panel");
            vexpand = true;
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            list = new ListBox ();
            list.add_css_class ("sx-layer-list");
            list.selection_mode = SelectionMode.NONE;
            list.activate_on_single_click = true;
            list.row_activated.connect (on_row_activated);
            scroll.child = list;
            append (scroll);
            var bar = new Box (Orientation.HORIZONTAL, 6);
            bar.add_css_class ("sx-layer-list-bar");
            bar.append (bar_button ("list-add-symbolic", _("New Layer"), () => add_layer ()));
            duplicate_button = bar_button ("edit-copy-symbolic", _("Duplicate Layer"), () => duplicate_layer ());
            bar.append (duplicate_button);
            up_button = bar_button ("go-up-symbolic", _("Move Up"), () => move_layer (1));
            bar.append (up_button);
            down_button = bar_button ("go-down-symbolic", _("Move Down"), () => move_layer (-1));
            bar.append (down_button);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            delete_button = bar_button ("user-trash-symbolic", _("Delete Layer"), () => delete_layer ());
            bar.append (delete_button);
            append (bar);
        }

        private delegate void Act ();

        private Button bar_button (string icon, string tooltip, owned Act action) {
            var b = new Button.from_icon_name (icon);
            b.tooltip_text = tooltip;
            b.update_property (AccessibleProperty.LABEL, tooltip, -1);
            b.clicked.connect (() => action ());
            return b;
        }

        private Publication pub {
            get { return win.doc.pub; }
        }

        private int index_of (int id) {
            for (int i = 0; i < pub.layers.size; i++) if (pub.layers[i].id == id) return i;
            return -1;
        }

        private Gee.ArrayList<Item> page_items (Layer l) {
            var out_items = new Gee.ArrayList<Item> ();
            int pi = win.canvas.active_page_index ();
            if (win.canvas.master_mode || pi < 0 || pi >= pub.pages.size) return out_items;
            var items = pub.pages[pi].items;
            for (int i = items.size - 1; i >= 0; i--) if (items[i].layer == l.id) out_items.add (items[i]);
            return out_items;
        }

        public void rebuild () {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            drop_row = null;
            if (win.doc == null) return;
            if (index_of (current) < 0) current = pub.layers.size > 0 ? pub.layers[pub.layers.size - 1].id : -1;
            for (int i = pub.layers.size - 1; i >= 0; i--) {
                var l = pub.layers[i];
                add_layer_row (l);
                if (expanded.contains (l.id)) foreach (var it in page_items (l)) add_item_row (it);
            }
            int idx = index_of (current);
            up_button.sensitive = idx >= 0 && idx < pub.layers.size - 1;
            down_button.sensitive = idx > 0;
            duplicate_button.sensitive = idx >= 0;
            delete_button.sensitive = idx >= 0 && pub.layers.size > 1;
        }

        private ToggleButton row_toggle (string on_icon, string off_icon, bool on, bool dim_when_off, string tooltip) {
            var t = new ToggleButton ();
            t.icon_name = on ? on_icon : off_icon;
            t.active = on;
            t.add_css_class ("flat");
            t.add_css_class ("sx-layer-toggle");
            t.valign = Align.CENTER;
            t.tooltip_text = tooltip;
            t.update_property (AccessibleProperty.LABEL, tooltip, -1);
            if (dim_when_off && !on) t.add_css_class ("sx-off");
            return t;
        }

        private void add_layer_row (Layer l) {
            var row = new ListBoxRow ();
            row.set_data<int> ("sx-layer", l.id + 1);
            if (l.id == current) row.add_css_class ("sx-layer-active");
            var box = new Box (Orientation.HORIZONTAL, 4);
            box.margin_start = box.margin_end = 4;
            box.margin_top = box.margin_bottom = 3;
            var objs = page_items (l);
            if (objs.size > 0) {
                bool open = expanded.contains (l.id);
                var exp = new Button.from_icon_name (open ? "pan-down-symbolic" : "pan-end-symbolic");
                exp.add_css_class ("flat");
                exp.add_css_class ("sx-layer-toggle");
                exp.valign = Align.CENTER;
                exp.tooltip_text = open ? _("Hide Objects") : _("Show Objects on This Page");
                exp.clicked.connect (() => {
                    if (expanded.contains (l.id)) expanded.remove (l.id);
                    else expanded.add (l.id);
                    rebuild ();
                });
                box.append (exp);
            } else {
                var pad = new Box (Orientation.HORIZONTAL, 0);
                pad.set_size_request (24, -1);
                box.append (pad);
            }
            var tag = new DrawingArea ();
            tag.set_size_request (3, 20);
            tag.valign = Align.CENTER;
            string col = l.color;
            tag.set_draw_func ((a, cr, w, h) => {
                var rgba = Gdk.RGBA ();
                if (!rgba.parse (col)) rgba.parse ("#888888");
                cr.set_source_rgb (rgba.red, rgba.green, rgba.blue);
                cr.arc (w / 2.0, w / 2.0, w / 2.0, Math.PI, 0);
                cr.arc (w / 2.0, h - w / 2.0, w / 2.0, 0, Math.PI);
                cr.close_path ();
                cr.fill ();
            });
            box.append (tag);
            var name_stack = new Stack ();
            name_stack.hexpand = true;
            name_stack.margin_start = 6;
            var texts = new Box (Orientation.VERTICAL, 0);
            texts.valign = Align.CENTER;
            var label = new Label (l.name);
            label.xalign = 0;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.add_css_class ("sx-layer-name");
            label.add_css_class ("sx-layer-is-layer");
            if (!l.visible) label.add_css_class ("dim-label");
            texts.append (label);
            int count = 0;
            pub.walk ((r) => {
                if (r.item.layer == l.id && r.group == null) count++;
                return true;
            });
            string info = ngettext ("%d object", "%d objects", count).printf (count);
            if (!l.printable) info += ", " + _("not printed");
            var sub = new Label (info);
            sub.xalign = 0;
            sub.add_css_class ("caption");
            sub.add_css_class ("dim-label");
            texts.append (sub);
            name_stack.add_named (texts, "label");
            var entry = new Entry ();
            entry.text = l.name;
            entry.add_css_class ("sx-layer-edit");
            entry.valign = Align.CENTER;
            name_stack.add_named (entry, "entry");
            name_stack.visible_child_name = "label";
            bool done = false;
            entry.activate.connect (() => finish_rename (l, entry, ref done));
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((kv, code, state) => {
                if (kv != Gdk.Key.Escape) return false;
                done = true;
                editing = -1;
                rebuild ();
                return true;
            });
            entry.add_controller (keys);
            var focus = new EventControllerFocus ();
            focus.leave.connect (() => {
                if (!done) Idle.add (() => {
                    if (!done) finish_rename (l, entry, ref done);
                    return Source.REMOVE;
                });
            });
            entry.add_controller (focus);
            box.append (name_stack);
            var vis = row_toggle ("view-reveal-symbolic", "view-conceal-symbolic", l.visible, true, l.visible ? _("Hide Layer") : _("Show Layer"));
            vis.toggled.connect (() => {
                if (l.visible == vis.active) return;
                win.edit (_("Layer Visibility"), () => l.visible = vis.active);
                rebuild ();
            });
            box.append (vis);
            var lock_btn = row_toggle ("changes-prevent-symbolic", "changes-allow-symbolic", l.locked, true, l.locked ? _("Unlock Layer") : _("Lock Layer"));
            lock_btn.toggled.connect (() => {
                if (l.locked == lock_btn.active) return;
                win.edit (_("Lock Layer"), () => l.locked = lock_btn.active);
                win.canvas.select_only (null);
                rebuild ();
            });
            box.append (lock_btn);
            row.child = box;
            var dbl = new GestureClick ();
            dbl.button = 1;
            dbl.pressed.connect ((n, x, y) => {
                if (n != 2) return;
                dbl.set_state (EventSequenceState.CLAIMED);
                start_rename (l, name_stack, entry);
            });
            row.add_controller (dbl);
            var right = new GestureClick ();
            right.button = 3;
            right.pressed.connect ((n, x, y) => {
                right.set_state (EventSequenceState.CLAIMED);
                show_menu (l, row, x, y, name_stack, entry);
            });
            row.add_controller (right);
            var drag = new DragSource ();
            drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect ((x, y) => {
                if (editing >= 0) return null;
                return new Gdk.ContentProvider.for_value ("sx-layer:%d".printf (l.id));
            });
            drag.drag_begin.connect ((d) => drag.set_icon (new WidgetPaintable (box), 12, 12));
            row.add_controller (drag);
            var drop = new DropTarget (typeof (string), Gdk.DragAction.MOVE);
            drop.motion.connect ((x, y) => {
                mark_drop (row, y < row.get_height () / 2.0);
                return Gdk.DragAction.MOVE;
            });
            drop.leave.connect (() => mark_drop (null, true));
            drop.drop.connect ((val, x, y) => {
                bool above = y < row.get_height () / 2.0;
                mark_drop (null, true);
                string s = (string) val;
                if (!s.has_prefix ("sx-layer:")) return false;
                int src = int.parse (s.substring (9));
                Idle.add (() => {
                    reorder (src, l.id, above);
                    return Source.REMOVE;
                });
                return true;
            });
            row.add_controller (drop);
            list.append (row);
            if (editing == l.id) start_rename (l, name_stack, entry);
        }

        private void add_item_row (Item it) {
            var row = new ListBoxRow ();
            row.set_data<Item> ("sx-item", it);
            if (win.canvas.selection.contains (it)) row.add_css_class ("sx-layer-selected");
            var box = new Box (Orientation.HORIZONTAL, 6);
            box.margin_start = 42;
            box.margin_end = 4;
            box.margin_top = box.margin_bottom = 4;
            var label = new Label (it.name != "" ? it.name : it.kind_label ());
            label.xalign = 0;
            label.hexpand = true;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.add_css_class ("sx-layer-name");
            box.append (label);
            row.child = box;
            list.append (row);
        }

        private void on_row_activated (ListBoxRow row) {
            var it = row.get_data<Item> ("sx-item");
            if (it != null) {
                win.canvas.select_only (it);
                return;
            }
            int id = row.get_data<int> ("sx-layer") - 1;
            if (id < 0) return;
            current = id;
            rebuild ();
        }

        private void mark_drop (ListBoxRow? row, bool above) {
            if (drop_row != null) {
                drop_row.remove_css_class ("sx-drop-before");
                drop_row.remove_css_class ("sx-drop-after");
            }
            drop_row = row;
            if (row != null) row.add_css_class (above ? "sx-drop-before" : "sx-drop-after");
        }

        private void reorder (int src, int target, bool above) {
            if (src == target) return;
            int si = index_of (src);
            if (si < 0 || index_of (target) < 0) return;
            win.edit (_("Move Layer"), () => {
                var l = pub.layers.remove_at (si);
                int ti = index_of (target);
                pub.layers.insert (above ? ti + 1 : ti, l);
            });
            current = src;
            rebuild ();
        }

        private void start_rename (Layer l, Stack name_stack, Entry entry) {
            editing = l.id;
            name_stack.visible_child_name = "entry";
            entry.grab_focus ();
            entry.select_region (0, -1);
        }

        private void finish_rename (Layer l, Entry entry, ref bool done) {
            if (done) return;
            done = true;
            editing = -1;
            string t = entry.text.strip ();
            if (t != "" && t != l.name) win.edit (_("Rename Layer"), () => l.name = t);
            rebuild ();
        }

        private void show_menu (Layer l, ListBoxRow row, double x, double y, Stack name_stack, Entry entry) {
            var menu = new ContextMenu (row);
            menu.add_item (_("Rename"), "document-edit-symbolic", () => start_rename (l, name_stack, entry));
            menu.add_item (l.printable ? _("Do Not Print") : _("Print This Layer"), "document-print-symbolic", () => {
                win.edit (_("Printable"), () => l.printable = !l.printable);
                rebuild ();
            });
            if (win.canvas.selection.size > 0) menu.add_item (_("Move Selection Here"), "mail-send-symbolic", () => {
                win.edit (_("Move to Layer"), () => {
                    foreach (var it in win.canvas.selection) it.layer = l.id;
                });
                rebuild ();
            });
            if (pub.layers.size > 1) {
                menu.add_separator ();
                menu.add_item (_("Delete"), "user-trash-symbolic", () => {
                    current = l.id;
                    delete_layer ();
                }, "destructive-action");
            }
            var rect = Gdk.Rectangle ();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = rect.height = 1;
            menu.set_pointing_to (rect);
            PublishWindow.popup_menu (menu);
        }

        private void add_layer () {
            Layer? made = null;
            win.edit (_("New Layer"), () => {
                made = new Layer (pub.next_id (), _("Layer %d").printf (pub.layers.size + 1));
                string[] colors = { "#4a86e8", "#e8554a", "#3fb56b", "#b04ae8", "#e8a24a", "#4ad4e8" };
                made.color = colors[pub.layers.size % colors.length];
                int ci = index_of (current);
                pub.layers.insert (ci >= 0 ? ci + 1 : pub.layers.size, made);
            });
            current = made.id;
            editing = made.id;
            rebuild ();
        }

        private void duplicate_layer () {
            int ci = index_of (current);
            if (ci < 0) return;
            var src = pub.layers[ci];
            Layer? copy = null;
            win.edit (_("Duplicate Layer"), () => {
                copy = src.clone ();
                copy.id = pub.next_id ();
                copy.name = _("%s Copy").printf (src.name);
                pub.layers.insert (ci + 1, copy);
                foreach (var page in pub.pages) {
                    var extra = new Gee.ArrayList<Item> ();
                    foreach (var it in page.items) if (it.layer == src.id) {
                        var dup = it.clone ();
                        pub.reassign (dup);
                        dup.layer = copy.id;
                        extra.add (dup);
                    }
                    page.items.add_all (extra);
                }
            });
            current = copy.id;
            rebuild ();
        }

        private void move_layer (int dir) {
            int ci = index_of (current);
            int ni = ci + dir;
            if (ci < 0 || ni < 0 || ni >= pub.layers.size) return;
            win.edit (_("Move Layer"), () => {
                var l = pub.layers.remove_at (ci);
                pub.layers.insert (ni, l);
            });
            rebuild ();
        }

        private void delete_layer () {
            int ci = index_of (current);
            if (ci < 0 || pub.layers.size < 2) return;
            var l = pub.layers[ci];
            win.edit (_("Delete Layer"), () => {
                var target = pub.layers[ci > 0 ? ci - 1 : 1];
                pub.walk ((r) => {
                    if (r.item.layer == l.id) r.item.layer = target.id;
                    return true;
                });
                pub.layers.remove (l);
            });
            current = -1;
            rebuild ();
        }
    }
}
