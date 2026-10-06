using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class SwatchButton : Button {
        public string spec;
        public bool allow_none = true;
        private PublishWindow win;
        private DrawingArea da;

        public signal void chosen (string spec);

        public SwatchButton (PublishWindow win, string spec, bool allow_none = true) {
            this.win = win;
            this.spec = spec;
            this.allow_none = allow_none;
            add_css_class ("flat");
            valign = Align.CENTER;
            tooltip_text = describe (spec);
            da = new DrawingArea ();
            da.set_size_request (34, 20);
            da.set_draw_func ((d, cr, w, h) => paint (cr, w, h, this.spec));
            child = da;
            clicked.connect (open_palette);
        }

        private string describe (string s) {
            if (s == ColorRef.NONE) return _("No Colour");
            if (ColorRef.is_swatch (s)) {
                double t = ColorRef.tint_of (s);
                return t < 99.99 ? "%s %d%%".printf (ColorRef.swatch_name (s), (int) t) : ColorRef.swatch_name (s);
            }
            return s;
        }

        private void paint (Cairo.Context cr, int w, int h, string s) {
            Renderer.round_rect (cr, 1, 1, w - 2, h - 2, 4);
            if (s == ColorRef.NONE) {
                cr.set_source_rgb (1, 1, 1);
                cr.fill_preserve ();
                cr.set_source_rgba (0, 0, 0, 0.25);
                cr.set_line_width (1);
                cr.stroke ();
                cr.set_source_rgb (0.86, 0.15, 0.15);
                cr.set_line_width (1.5);
                cr.move_to (3, h - 3);
                cr.line_to (w - 3, 3);
                cr.stroke ();
                return;
            }
            var c = win.doc.pub.resolve (s);
            cr.set_source_rgba (c.r, c.g, c.b, 1);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.25);
            cr.set_line_width (1);
            cr.stroke ();
        }

        public void set_spec (string s) {
            spec = s;
            tooltip_text = describe (s);
            da.queue_draw ();
        }

        private void open_palette () {
            var pop = new Popover ();
            pop.set_parent (this);
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 10;
            var title = new Label (_("Swatches"));
            title.add_css_class ("caption");
            title.add_css_class ("dim-label");
            title.xalign = 0;
            box.append (title);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 8;
            flow.min_children_per_line = 6;
            flow.column_spacing = 4;
            flow.row_spacing = 4;
            double tint = ColorRef.tint_of (spec);
            var tint_spin = new SpinButton.with_range (0, 100, 5);
            tint_spin.value = tint;
            foreach (var sw in win.doc.pub.swatches) {
                if (sw.name == "Registration") continue;
                var b = new Button ();
                b.add_css_class ("flat");
                b.add_css_class ("publish-swatch");
                b.tooltip_text = "%s (%s)%s".printf (sw.name, sw.describe (), sw.spot ? " " + _("Spot") : "");
                var d = new DrawingArea ();
                d.set_size_request (20, 20);
                string sspec = ColorRef.swatch (sw.name);
                d.set_draw_func ((dd, cr, w, h) => {
                    var c = win.doc.pub.resolve (sspec);
                    Renderer.round_rect (cr, 1, 1, w - 2, h - 2, 4);
                    cr.set_source_rgba (c.r, c.g, c.b, 1);
                    cr.fill ();
                    if (sw.spot) {
                        cr.set_source_rgb (1, 1, 1);
                        cr.arc (w - 5, h - 5, 2.5, 0, 2 * Math.PI);
                        cr.fill ();
                    }
                });
                b.child = d;
                string name = sw.name;
                b.clicked.connect (() => {
                    pop.popdown ();
                    string s = ColorRef.swatch (name, tint_spin.value);
                    set_spec (s);
                    chosen (s);
                });
                flow.append (b);
            }
            box.append (flow);
            var tint_row = new Box (Orientation.HORIZONTAL, 8);
            var tl = new Label (_("Tint %"));
            tl.hexpand = true;
            tl.xalign = 0;
            tint_row.append (tl);
            tint_row.append (tint_spin);
            tint_spin.value_changed.connect (() => {
                if (!ColorRef.is_swatch (spec)) return;
                string s = ColorRef.with_tint (spec, tint_spin.value);
                set_spec (s);
                chosen (s);
            });
            box.append (tint_row);
            var actions = new Box (Orientation.HORIZONTAL, 6);
            if (allow_none) {
                var none = new Button.with_label (_("None"));
                none.clicked.connect (() => {
                    pop.popdown ();
                    set_spec (ColorRef.NONE);
                    chosen (ColorRef.NONE);
                });
                actions.append (none);
            }
            var add = new Button.with_label (_("New Swatch…"));
            add.hexpand = true;
            add.clicked.connect (() => {
                pop.popdown ();
                Dialogs.edit_swatch (win, null, (name) => {
                    string s = ColorRef.swatch (name);
                    set_spec (s);
                    chosen (s);
                });
            });
            actions.append (add);
            box.append (actions);
            pop.child = box;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }
    }

    public class Inspector : Box {
        public PublishWindow win;
        private Box content;
        public bool syncing = false;
        private SpinRow? x_row = null;
        private SpinRow? y_row = null;
        private SpinRow? w_row = null;
        private SpinRow? h_row = null;
        private SpinRow? r_row = null;
        private uint text_sync = 0;

        public Inspector (PublishWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.add_css_class ("publish-panel-scroll");
            content = new Box (Orientation.VERTICAL, 18);
            content.add_css_class ("publish-panel");
            scroll.child = content;
            append (scroll);
        }

        public Document doc {
            get { return win.doc; }
        }

        public Publication pub {
            get { return win.doc.pub; }
        }

        public PageCanvas canvas {
            get { return win.canvas; }
        }

        public string unit {
            owned get { return pub.settings.units; }
        }

        public void edit (string label, owned Document.EditFunc f, string key = "") {
            if (syncing) return;
            win.edit (label, (owned) f, key);
        }

        public PreferencesGroup group (string title, string? desc = null) {
            var g = new PreferencesGroup (title, desc);
            content.append (g);
            return g;
        }

        public delegate void SpinApply (double v);
        public delegate void BoolApply (bool v);
        public delegate void StringApply (string v);

        public SpinRow spin (PreferencesGroup g, string title, double min, double max, double step, double value, int digits, owned SpinApply apply, string key) {
            var row = new SpinRow (title, null, min, max, step, value);
            row.spin_btn.digits = digits;
            row.spin_btn.value_changed.connect (() => {
                double v = row.spin_btn.value;
                edit (title, () => apply (v), key);
            });
            g.add_row (row);
            return row;
        }

        public SpinRow len (PreferencesGroup g, string title, double pt, owned SpinApply apply, string key, double min = -10000) {
            string u = unit;
            double f = Units.factor (u);
            int digits = u == "pt" || u == "px" ? 1 : (u == "in" ? 3 : 2);
            double step = u == "in" ? 0.0625 : (u == "cm" ? 0.1 : 1);
            var row = spin (g, "%s (%s)".printf (title, u), min / f, 100000, step, Math.round (pt / f * 1000) / 1000, digits, (v) => apply (v * f), key);
            return row;
        }

        public SwitchRow toggle (PreferencesGroup g, string title, string? subtitle, bool value, owned BoolApply apply) {
            var row = new SwitchRow (title, subtitle, value);
            row.switch_btn.notify["active"].connect (() => {
                bool v = row.switch_btn.active;
                edit (title, () => apply (v));
            });
            g.add_row (row);
            return row;
        }

        public SelectionRow choice (PreferencesGroup g, string title, owned string[] labels, int current, owned SpinApply apply) {
            var row = new SelectionRow (title, labels, current >= 0 && current < labels.length ? labels[current] : "");
            row.selected.connect ((item) => {
                for (int i = 0; i < labels.length; i++) {
                    if (labels[i] == item) {
                        int v = i;
                        edit (title, () => apply (v));
                        break;
                    }
                }
            });
            g.add_row (row);
            return row;
        }

        public SwatchButton color_row (PreferencesGroup g, string title, string spec, bool allow_none, owned StringApply apply) {
            var row = new ActionRow (title);
            var b = new SwatchButton (win, spec, allow_none);
            b.chosen.connect ((s) => edit (title, () => apply (s)));
            row.add_suffix (b);
            g.add_row (row);
            return b;
        }

        public Box tool_row (PreferencesGroup g, string title) {
            var row = new ActionRow (title);
            var box = new Box (Orientation.HORIZONTAL, 2);
            box.valign = Align.CENTER;
            row.add_suffix (box);
            g.add_row (row);
            return box;
        }

        public Button tool (Box box, string icon, string fallback, string tip, string action) {
            var theme = IconTheme.get_for_display (Gdk.Display.get_default ());
            var b = new Button.from_icon_name (theme.has_icon (icon) ? icon : fallback);
            b.add_css_class ("flat");
            b.tooltip_text = tip;
            b.action_name = action;
            box.append (b);
            return b;
        }

        public ActionRow button_row (PreferencesGroup g, string title, string? subtitle, string label, owned Document.EditFunc f) {
            var row = new ActionRow (title, subtitle);
            var b = new Button.with_label (label);
            b.valign = Align.CENTER;
            b.clicked.connect (() => f ());
            row.add_suffix (b);
            g.add_row (row);
            return row;
        }

        public void rebuild () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            x_row = y_row = w_row = h_row = r_row = null;
            if (doc == null) return;
            syncing = true;
            var sel = canvas.selection;
            if (canvas.edit != null) {
                build_text_formatting ();
                if (canvas.edit.frame != null) build_frame_options (canvas.edit.frame);
            } else if (sel.size == 0) {
                build_page ();
            } else if (sel.size == 1) {
                var it = sel[0];
                build_geometry (it);
                switch (it.kind) {
                    case ItemKind.TEXT:
                        build_text_formatting ();
                        build_frame_options ((TextFrame) it);
                        break;
                    case ItemKind.IMAGE:
                        build_image ((ImageFrame) it);
                        ProInspector.image (this, (ImageFrame) it);
                        break;
                    case ItemKind.TABLE:
                        build_table ((TableItem) it);
                        ProInspector.table (this, (TableItem) it);
                        build_text_formatting ();
                        break;
                    case ItemKind.SHAPE:
                        if (it is WordArtItem) ProInspector.wordart (this, (WordArtItem) it);
                        build_shape ((ShapeItem) it);
                        break;
                    default:
                        break;
                }
                build_appearance (it);
                ProInspector.effects (this, it);
                build_wrap (it);
                ProInspector.object_extras (this, it);
                build_object (it);
                build_merge_rule (it);
                build_form (it);
                build_liquid (it);
            } else {
                build_multi ();
                ProInspector.multi (this, sel);
            }
            syncing = false;
        }

        public void sync_geometry () {
            if (canvas.selection.size != 1 || x_row == null) return;
            var it = canvas.selection[0];
            double f = Units.factor (unit);
            syncing = true;
            x_row.value = Math.round (it.x / f * 100) / 100;
            y_row.value = Math.round (it.y / f * 100) / 100;
            w_row.value = Math.round (it.w / f * 100) / 100;
            h_row.value = Math.round (it.h / f * 100) / 100;
            if (r_row != null) r_row.value = it.rotation;
            syncing = false;
        }

        public void sync_text () {
            if (text_sync != 0) Source.remove (text_sync);
            text_sync = Timeout.add (160, () => {
                text_sync = 0;
                if (!syncing && get_mapped ()) rebuild ();
                return Source.REMOVE;
            });
        }

        private void build_page () {
            int pi = canvas.active_page_index ();
            var s = pub.settings;
            var g = group (canvas.master_mode ? _("Master Page") : _("Page %s").printf (pub.page_label (pi)));
            var summary = new ActionRow (_("Size"), "%s × %s, %s".printf (Units.format (s.width, unit), Units.format (s.height, unit), s.facing ? _("facing pages") : _("single pages")));
            g.add_row (summary);
            button_row (g, _("Document Setup"), _("Size, margins, columns, bleed and baseline grid"), _("Edit…"), () => win.run ("document-setup"));
            if (!canvas.master_mode && pi >= 0) {
                var pg = pub.pages[pi];
                string[] names = { _("None") };
                int cur = 0;
                for (int i = 0; i < pub.masters.size; i++) {
                    names += pub.masters[i].display_name ();
                    if (pub.masters[i].id == pg.master) cur = i + 1;
                }
                choice (g, _("Master"), names, cur, (v) => {
                    pg.master = v == 0 ? "" : pub.masters[(int) v - 1].id;
                    win.pages_panel.load ();
                });
                toggle (g, _("Show Master Items"), null, !pg.hide_master, (v) => pg.hide_master = !v);
                var tg = group (_("Page Transition"), _("Used when the exported PDF is shown full screen"));
                var tl = PageTransition.labels ();
                var ts = PageTransition.styles ();
                int tcur = 0;
                for (int i = 0; i < ts.length; i++) if (ts[i] == pg.transition) tcur = i;
                choice (tg, _("Effect"), tl, tcur, (v) => pg.transition = ts[(int) v]);
                if (pg.transition != "") spin (tg, _("Duration (seconds)"), 0.1, 10, 0.1, pg.transition_duration, 1, (v) => pg.transition_duration = v, "trans-d");
                var sg = group (_("Page Size"), _("Pages of one publication can have different sizes, for example a fold-out or a cover with spine"));
                toggle (sg, _("Own Size"), _("This page does not use the document size"), !pg.width.is_nan (), (v) => {
                    pg.width = v ? s.width : double.NAN;
                    pg.height = v ? s.height : double.NAN;
                    Idle.add (() => {
                        canvas.relayout ();
                        win.pages_panel.load ();
                        rebuild ();
                        return Source.REMOVE;
                    });
                });
                if (!pg.width.is_nan ()) {
                    len (sg, _("Page Width"), pg.width, (v) => {
                        pg.width = double.max (36, v);
                        canvas.relayout ();
                    }, "pg-w", 36);
                    len (sg, _("Page Height"), pg.height, (v) => {
                        pg.height = double.max (36, v);
                        canvas.relayout ();
                    }, "pg-h", 36);
                }
                if (pi > 0) toggle (sg, _("Join to Previous Spread"), _("Spreads of three or more pages, such as gatefolds"), pg.join_prev, (v) => {
                    pg.join_prev = v;
                    Idle.add (() => {
                        canvas.relayout ();
                        win.pages_panel.load ();
                        return Source.REMOVE;
                    });
                });
                button_row (g, _("Numbering and Sections"), pub.section_for (pi).name != "" ? pub.section_for (pi).name : null, _("Edit…"), () => Dialogs.sections (win, pi));
            } else if (canvas.master_mode) {
                var m = pub.master (canvas.master_id);
                if (m != null) {
                    var ng = new EntryRow (_("Name"));
                    ng.text = m.name;
                    ng.entry_changed.connect (() => {
                        string t = ng.text.strip ();
                        if (t == "") return;
                        edit (_("Rename Master"), () => m.name = t, "rename-master");
                        win.pages_panel.load ();
                    });
                    g.add_row (ng);
                    string[] names = { _("None") };
                    int cur = 0;
                    var others = new Gee.ArrayList<MasterPage> ();
                    foreach (var o in pub.masters) if (o != m) others.add (o);
                    for (int i = 0; i < others.size; i++) {
                        names += others[i].display_name ();
                        if (others[i].id == m.based_on) cur = i + 1;
                    }
                    choice (g, _("Based On"), names, cur, (v) => {
                        string target = v == 0 ? "" : others[(int) v - 1].id;
                        bool cycle = false;
                        if (target != "") foreach (var c in pub.master_chain (target)) if (c == m) cycle = true;
                        if (!cycle) m.based_on = target;
                    });
                }
            }
            var gg = group (_("Guides"), _("Drag from the rulers to add a guide, drag it back to remove it"));
            button_row (gg, _("Create Guides"), _("Rows and columns of guides with gutters"), _("Create…"), () => win.run ("create-guides"));
            var t = new SwitchRow (_("Show Baseline Grid"), _("Every %s from %s").printf (Units.format (s.baseline_step, unit), Units.format (s.baseline_start, unit)), canvas.show_baseline);
            t.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                if (canvas.show_baseline != t.switch_btn.active) win.run ("show-baseline");
            });
            gg.add_row (t);
            var hy = group (_("Hyphenation"));
            hy.add_row (new ActionRow (_("Dictionary"), Hyphenator.describe ("en")));
        }

        private void build_multi () {
            var sel = canvas.selection;
            var g = group (_("Selection"), ngettext ("%d object", "%d objects", sel.size).printf (sel.size));
            var box = tool_row (g, _("Align"));
            tool (box, "publish-align-left-symbolic", "format-justify-left-symbolic", _("Left Edges"), "win.arrange-left");
            tool (box, "publish-align-center-h-symbolic", "format-justify-center-symbolic", _("Horizontal Centers"), "win.arrange-center");
            tool (box, "publish-align-right-symbolic", "format-justify-right-symbolic", _("Right Edges"), "win.arrange-right");
            var box2 = tool_row (g, _("Align Vertically"));
            tool (box2, "publish-align-top-symbolic", "go-top-symbolic", _("Top Edges"), "win.arrange-top");
            tool (box2, "publish-align-center-v-symbolic", "format-justify-fill-symbolic", _("Vertical Centers"), "win.arrange-middle");
            tool (box2, "publish-align-bottom-symbolic", "go-bottom-symbolic", _("Bottom Edges"), "win.arrange-bottom");
            var box3 = tool_row (g, _("Distribute"));
            tool (box3, "publish-distribute-h-symbolic", "view-continuous-symbolic", _("Horizontally"), "win.distribute-h");
            tool (box3, "publish-distribute-v-symbolic", "view-paged-symbolic", _("Vertically"), "win.distribute-v");
            var box4 = tool_row (g, _("Group"));
            tool (box4, "publish-group-symbolic", "object-group-symbolic", _("Group (Ctrl+G)"), "win.group");
            tool (box4, "publish-ungroup-symbolic", "object-ungroup-symbolic", _("Ungroup (Ctrl+Shift+G)"), "win.ungroup");
            var ap = group (_("Appearance"));
            double op = sel[0].opacity;
            spin (ap, _("Opacity %"), 0, 100, 5, Math.round (op * 100), 0, (v) => {
                foreach (var it in canvas.selection) it.opacity = v / 100;
            }, "multi-opacity");
            color_row (ap, _("Fill"), sel[0].fill.color, true, (s) => {
                foreach (var it in canvas.selection) it.fill = new Fill.solid (s);
            });
            color_row (ap, _("Stroke"), sel[0].stroke.color, true, (s) => {
                foreach (var it in canvas.selection) it.stroke.color = s;
            });
        }

        private void build_geometry (Item it) {
            var g = group (it.kind_label ());
            x_row = len (g, _("X"), it.x, (v) => {
                var gi = it as GroupItem;
                if (gi != null) gi.move_by (v - gi.x, 0);
                else it.x = v;
            }, "geo-x");
            y_row = len (g, _("Y"), it.y, (v) => {
                var gi = it as GroupItem;
                if (gi != null) gi.move_by (0, v - gi.y);
                else it.y = v;
            }, "geo-y");
            w_row = len (g, _("Width"), it.w, (v) => resize (it, v, it.h), "geo-w", 0);
            h_row = len (g, _("Height"), it.h, (v) => resize (it, it.w, v), "geo-h", 0);
            r_row = spin (g, _("Rotation"), -180, 180, 1, it.rotation, 1, (v) => it.rotation = v, "geo-r");
            var box = tool_row (g, _("Transform"));
            tool (box, "object-flip-horizontal-symbolic", "object-flip-horizontal-symbolic", _("Flip Horizontal"), "win.flip-h");
            tool (box, "object-flip-vertical-symbolic", "object-flip-vertical-symbolic", _("Flip Vertical"), "win.flip-v");
            tool (box, "object-rotate-left-symbolic", "object-rotate-left-symbolic", _("Rotate 90° Counterclockwise"), "win.rotate-ccw");
            tool (box, "object-rotate-right-symbolic", "object-rotate-right-symbolic", _("Rotate 90° Clockwise"), "win.rotate-cw");
        }

        private void resize (Item it, double w, double h) {
            w = double.max (w, 1);
            h = double.max (h, 0);
            var from = it.box ();
            var to = Rect (it.x, it.y, w, h);
            var g = it as GroupItem;
            if (g != null) g.scale_children (from, to);
            var tb = it as TableItem;
            if (tb != null) tb.scale_to (w, h);
            it.w = w;
            it.h = h;
        }

        private void build_appearance (Item it) {
            if (it is GroupItem) {
                var g = group (_("Appearance"));
                spin (g, _("Opacity %"), 0, 100, 5, Math.round (it.opacity * 100), 0, (v) => it.opacity = v / 100, "opacity");
                build_shadow (g, it);
                return;
            }
            bool is_line = it is ShapeItem && ((ShapeItem) it).shape == ShapeKind.LINE;
            var g = group (_("Appearance"));
            if (!is_line) {
                string[] kinds = { _("None"), _("Solid"), _("Linear Gradient"), _("Radial Gradient"), _("Pattern"), _("Texture"), _("Picture") };
                choice (g, _("Fill"), kinds, (int) it.fill.kind, (v) => {
                    var k = (FillKind) (int) v;
                    string a = it.fill.color != ColorRef.NONE ? it.fill.color : ColorRef.swatch ("Cyan");
                    if (k == FillKind.NONE) it.fill = new Fill ();
                    else if (k == FillKind.SOLID) it.fill = new Fill.solid (a);
                    else if (k == FillKind.PATTERN || k == FillKind.TEXTURE || k == FillKind.PICTURE) {
                        var f = new Fill.solid (it.fill.kind == FillKind.SOLID ? it.fill.color : ColorRef.BLACK);
                        f.kind = k;
                        f.pattern = "diag-up";
                        f.texture = "paper";
                        f.tile = k == FillKind.TEXTURE;
                        it.fill = f;
                    } else {
                        var f = new Fill.linear (a, ColorRef.PAPER, 90);
                        f.kind = k;
                        it.fill = f;
                    }
                    Idle.add (() => {
                        rebuild ();
                        return Source.REMOVE;
                    });
                });
                if (it.fill.kind == FillKind.SOLID) {
                    color_row (g, _("Fill Colour"), it.fill.color, false, (s) => it.fill.color = s);
                } else if (it.fill.kind == FillKind.LINEAR || it.fill.kind == FillKind.RADIAL) {
                    while (it.fill.stops.size < 2) it.fill.stops.add (new GradientStop (it.fill.stops.size, ColorRef.PAPER));
                    color_row (g, _("Start Colour"), it.fill.stops[0].color, false, (s) => {
                        it.fill.stops[0].color = s;
                        it.fill.color = s;
                    });
                    color_row (g, _("End Colour"), it.fill.stops[it.fill.stops.size - 1].color, false, (s) => it.fill.stops[it.fill.stops.size - 1].color = s);
                    spin (g, _("End Opacity %"), 0, 100, 5, Math.round (it.fill.stops[it.fill.stops.size - 1].opacity * 100), 0, (v) => it.fill.stops[it.fill.stops.size - 1].opacity = v / 100, "grad-op");
                    if (it.fill.kind == FillKind.LINEAR) spin (g, _("Angle"), -180, 180, 15, it.fill.angle, 0, (v) => it.fill.angle = v, "grad-angle");
                } else {
                    ProInspector.fill_extras (this, g, it);
                }
            }
            color_row (g, _("Stroke"), it.stroke.color, true, (s) => it.stroke.color = s);
            if (it.stroke.visible () || is_line) {
                spin (g, _("Stroke Weight (pt)"), 0, 100, 0.25, it.stroke.width, 2, (v) => it.stroke.width = v, "stroke-w");
                string[] dashes = { _("Solid"), _("Dashed"), _("Dotted"), _("Dash Dot") };
                choice (g, _("Stroke Type"), dashes, (int) it.stroke.dash, (v) => it.stroke.dash = (DashKind) (int) v);
                if (is_line) {
                    string[] heads = { _("None"), _("Arrow"), _("Circle") };
                    choice (g, _("Start"), heads, it.stroke.arrow_start, (v) => it.stroke.arrow_start = (int) v);
                    choice (g, _("End"), heads, it.stroke.arrow_end, (v) => it.stroke.arrow_end = (int) v);
                }
            }
            spin (g, _("Opacity %"), 0, 100, 5, Math.round (it.opacity * 100), 0, (v) => it.opacity = v / 100, "opacity");
            if (!is_line && !(it is ShapeItem && ((ShapeItem) it).shape != ShapeKind.RECT)) {
                string[] corners = { _("None"), _("Rounded"), _("Bevel"), _("Inset"), _("Inverse Rounded") };
                choice (g, _("Corners"), corners, (int) it.corner, (v) => {
                    it.corner = (CornerKind) (int) v;
                    if (it.corner != CornerKind.NONE && it.corner_radius < 1) it.corner_radius = 12;
                });
                if (it.corner != CornerKind.NONE) len (g, _("Corner Size"), it.corner_radius, (v) => it.corner_radius = double.max (0, v), "corner", 0);
            }
            build_shadow (g, it);
        }

        private void build_shadow (PreferencesGroup g, Item it) {
            toggle (g, _("Drop Shadow"), null, it.shadow.enabled, (v) => {
                it.shadow.enabled = v;
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (!it.shadow.enabled) return;
            spin (g, _("Shadow Offset X (pt)"), -100, 100, 0.5, it.shadow.dx, 1, (v) => it.shadow.dx = v, "sh-dx");
            spin (g, _("Shadow Offset Y (pt)"), -100, 100, 0.5, it.shadow.dy, 1, (v) => it.shadow.dy = v, "sh-dy");
            spin (g, _("Shadow Blur (pt)"), 0, 60, 0.5, it.shadow.blur, 1, (v) => it.shadow.blur = v, "sh-blur");
            spin (g, _("Shadow Opacity %"), 0, 100, 5, Math.round (it.shadow.opacity * 100), 0, (v) => it.shadow.opacity = v / 100, "sh-op");
            color_row (g, _("Shadow Colour"), it.shadow.color, false, (s) => it.shadow.color = s);
        }

        private void build_wrap (Item it) {
            var g = group (_("Text Wrap"), _("How text in other frames flows around this object"));
            string[] modes = { _("None"), _("Square"), _("Tight"), _("Top and Bottom"), _("Through"), _("Behind Text"), _("In Front of Text") };
            choice (g, _("Wrap"), modes, (int) it.wrap, (v) => {
                it.wrap = (WrapMode) (int) v;
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            ProInspector.wrap_extras (this, g, it);
            if (!it.wrap.wraps ()) return;
            len (g, _("Offset"), it.wrap_offset, (v) => it.wrap_offset = v, "wrap-off");
            if (it.wrap != WrapMode.JUMP) {
                string[] sides = { _("Both Sides"), _("Largest Area"), _("Left Side"), _("Right Side") };
                choice (g, _("Wrap To"), sides, (int) it.wrap_side, (v) => it.wrap_side = (WrapSide) (int) v);
            }
            var im = it as ImageFrame;
            if (it.wrap == WrapMode.CONTOUR && im != null) {
                string[] sources = { _("Automatic"), _("Detect Edges"), _("Picture Path"), _("Frame Shape") };
                var row = choice (g, _("Contour"), sources, im.contour_source.clamp (0, 3), (v) => im.contour_source = (int) v);
                var paths = ImageStore.get_default ().image_paths (pub, im);
                if (paths != null) {
                    var path = paths.preferred ();
                    row.subtitle = _("Picture path \"%s\"").printf (path.name);
                    toggle (g, _("Clip to Picture Path"), _("Hide the parts of the picture outside its path"), im.clip_path, (v) => im.clip_path = v);
                } else if (im.contour_source == ImageStore.CONTOUR_PATH) {
                    row.subtitle = _("This picture has no saved path");
                } else {
                    row.subtitle = _("Transparent edges when the picture has them");
                }
            }
        }

        private void build_object (Item it) {
            var g = group (_("Object"));
            var name = new EntryRow (_("Name"));
            name.text = it.name;
            name.entry_changed.connect (() => edit (_("Name"), () => it.name = name.text, "name"));
            g.add_row (name);
            string[] names = new string[pub.layers.size];
            int cur = 0;
            for (int i = 0; i < pub.layers.size; i++) {
                names[i] = pub.layers[i].name;
                if (pub.layers[i].id == it.layer) cur = i;
            }
            choice (g, _("Layer"), names, cur, (v) => it.layer = pub.layers[(int) v].id);
            toggle (g, _("Locked"), null, it.locked, (v) => it.locked = v);
            toggle (g, _("Nonprinting"), _("Shown on screen, left out of PDF and print"), it.nonprinting, (v) => it.nonprinting = v);
            var box = tool_row (g, _("Arrange"));
            tool (box, "publish-bring-front-symbolic", "go-top-symbolic", _("Bring to Front"), "win.bring-front");
            tool (box, "go-up-symbolic", "go-up-symbolic", _("Bring Forward"), "win.bring-forward");
            tool (box, "go-down-symbolic", "go-down-symbolic", _("Send Backward"), "win.send-backward");
            tool (box, "publish-send-back-symbolic", "go-bottom-symbolic", _("Send to Back"), "win.send-back");
        }

        private void build_liquid (Item it) {
            var g = group (_("Liquid Layout"), _("How this object adapts in alternate layouts of another size"));
            choice (g, _("Rule"), LiquidMode.labels (), it.liquid_mode.clamp (0, 3), (v) => {
                it.liquid_mode = (int) v;
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (it.liquid_mode != (int) LiquidMode.OBJECT) return;
            string[] names = { _("Pin Left"), _("Pin Right"), _("Pin Top"), _("Pin Bottom"), _("Resize Width"), _("Resize Height") };
            int[] bits = { Liquid.PIN_LEFT, Liquid.PIN_RIGHT, Liquid.PIN_TOP, Liquid.PIN_BOTTOM, Liquid.FLEX_W, Liquid.FLEX_H };
            for (int i = 0; i < names.length; i++) {
                int bit = bits[i];
                toggle (g, names[i], null, (it.liquid_pins & bit) != 0, (v) => {
                    if (v) it.liquid_pins |= bit;
                    else it.liquid_pins &= ~bit;
                });
            }
        }

        private void build_form (Item it) {
            if (it is GroupItem || it is TableItem) return;
            var g = group (_("PDF Form and Button"), _("In exported PDF files this object becomes a fillable field or a button"));
            var kinds = FormKind.labels ();
            int cur = it.form != null ? (int) it.form.kind : 0;
            choice (g, _("Interactive Role"), kinds, cur, (v) => {
                if (v == 0) it.form = null;
                else {
                    if (it.form == null) it.form = new FormSpec ();
                    it.form.kind = (FormKind) (int) v;
                }
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (it.form == null || it.form.kind == FormKind.NONE) return;
            var f = it.form;
            var nm = new EntryRow (_("Field Name"));
            nm.text = f.name;
            nm.entry_changed.connect (() => edit (_("Field Name"), () => f.name = nm.text.strip (), "form-name"));
            g.add_row (nm);
            var tip = new EntryRow (_("Tooltip"));
            tip.text = f.tooltip;
            tip.entry_changed.connect (() => edit (_("Tooltip"), () => f.tooltip = tip.text, "form-tip"));
            g.add_row (tip);
            if (f.kind == FormKind.CHOICE) {
                var opts = new EntryRow (_("Choices, Separated by Commas"));
                opts.text = f.options;
                opts.entry_changed.connect (() => edit (_("Choices"), () => f.options = opts.text, "form-opts"));
                g.add_row (opts);
            }
            if (f.kind == FormKind.BUTTON) {
                var act = new EntryRow (_("Action: page:N, next, previous, print or a web address"));
                act.text = f.action;
                act.entry_changed.connect (() => edit (_("Button Action"), () => f.action = act.text.strip (), "form-act"));
                g.add_row (act);
            } else {
                toggle (g, _("Required"), null, f.required, (v) => f.required = v);
                if (f.kind == FormKind.TEXT) toggle (g, _("Several Lines"), null, f.multiline, (v) => f.multiline = v);
            }
        }

        private void build_merge_rule (Item it) {
            if (!pub.merge.active ()) return;
            var g = group (_("Data Merge Rule"), _("Show this object only for the records that match"));
            string[] fields = { _("Every Record") };
            int cur = 0;
            for (int i = 0; i < pub.merge.fields.size; i++) {
                fields += pub.merge.fields[i];
                if (it.show_when != null && pub.merge.fields[i] == it.show_when.field) cur = i + 1;
            }
            choice (g, _("Show For"), fields, cur, (v) => {
                if (v == 0) it.show_when = null;
                else if (it.show_when == null) it.show_when = new MergeFilter (pub.merge.fields[(int) v - 1], FilterOp.NOT_EMPTY, "");
                else it.show_when.field = pub.merge.fields[(int) v - 1];
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (it.show_when == null) return;
            var ops = FilterOp.all ();
            string[] labels = {};
            int oc = 0;
            for (int i = 0; i < ops.length; i++) {
                labels += ops[i].label ();
                if (ops[i] == it.show_when.op) oc = i;
            }
            choice (g, _("Condition"), labels, oc, (v) => {
                it.show_when.op = ops[(int) v];
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (it.show_when.op != FilterOp.EMPTY && it.show_when.op != FilterOp.NOT_EMPTY) {
                var val = new EntryRow (_("Value"));
                val.text = it.show_when.value;
                val.entry_changed.connect (() => edit (_("Data Merge Rule"), () => it.show_when.value = val.text, "when-value"));
                g.add_row (val);
            }
        }

        private void build_shape (ShapeItem s) {
            if (s.shape != ShapeKind.POLYGON && s.shape != ShapeKind.STAR) return;
            var g = group (s.shape.label ());
            spin (g, s.shape == ShapeKind.STAR ? _("Points") : _("Sides"), 3, 64, 1, s.sides, 0, (v) => s.sides = (int) v, "sides");
            if (s.shape == ShapeKind.STAR) spin (g, _("Inner Radius %"), 5, 100, 5, Math.round (s.star_inset * 100), 0, (v) => s.star_inset = v / 100, "inset");
        }

        private void build_image (ImageFrame im) {
            var g = group (_("Picture"));
            var st = ImageStore.status (pub, im);
            var inf = ImageStore.get_default ().info (pub, im);
            string sub = im.link != "" ? im.link : (im.media != "" ? _("Embedded in the publication") : _("No picture placed"));
            var row = new ActionRow (ImageStore.status_label (st), sub);
            g.add_row (row);
            if (inf != null) {
                var pl = ImageStore.place (im, inf);
                double ppi = double.min (pl.ppi_x (), pl.ppi_y ());
                string cs = inf.components == 4 ? "CMYK" : (inf.components == 1 ? _("Grayscale") : "RGB");
                g.add_row (new ActionRow (_("Effective Resolution"), _("%d ppi, %d × %d px, %s").printf ((int) Math.round (ppi), inf.width, inf.height, cs)));
            }
            button_row (g, _("Place Picture"), null, _("Choose…"), () => win.run ("place"));
            if (im.link != "") button_row (g, _("Relink"), null, _("Choose…"), () => win.relink.begin (im));
            if (im.link != "" && st == LinkStatus.MODIFIED) button_row (g, _("Update Link"), null, _("Update"), () => win.update_link (im));
            if (im.link != "") button_row (g, _("Embed"), _("Keep a copy inside the publication"), _("Embed"), () => win.embed_image (im));
            if (im.media != "" && im.link == "") button_row (g, _("Unembed"), _("Save the picture next to the publication and link it"), _("Unembed"), () => win.unembed_image (im));
            string[] fits = { _("Fill Frame"), _("Fit Content"), _("Stretch"), _("Manual") };
            choice (g, _("Fitting"), fits, (int) im.fit, (v) => {
                if ((FitMode) (int) v == FitMode.MANUAL && inf != null) ImageStore.to_manual (im, inf);
                else im.fit = (FitMode) (int) v;
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            if (im.fit == FitMode.MANUAL) {
                spin (g, _("Scale %"), 1, 2000, 1, Math.round (im.img_scale * 1000) / 10, 1, (v) => im.img_scale = v / 100, "img-scale");
                len (g, _("Offset X"), im.img_x, (v) => im.img_x = v, "img-x");
                len (g, _("Offset Y"), im.img_y, (v) => im.img_y = v, "img-y");
            } else if (im.fit != FitMode.STRETCH) {
                spin (g, _("Focus X %"), 0, 100, 5, Math.round (im.focus_x * 100), 0, (v) => im.focus_x = v / 100, "focus-x");
                spin (g, _("Focus Y %"), 0, 100, 5, Math.round (im.focus_y * 100), 0, (v) => im.focus_y = v / 100, "focus-y");
            }
            var art = ImageStore.get_default ().vector (pub, im);
            if (art != null && art.kind == "pdf" && art.pages > 1) spin (g, _("PDF Page"), 1, art.pages, 1, im.pdf_page + 1, 0, (v) => im.pdf_page = (int) v - 1, "pdf-page");
            toggle (g, _("Ellipse Frame"), null, im.shape_ellipse, (v) => im.shape_ellipse = v);
            if (pub.merge.active ()) {
                string[] fields = { _("None") };
                int cur = 0;
                for (int i = 0; i < pub.merge.fields.size; i++) {
                    fields += pub.merge.fields[i];
                    if (pub.merge.fields[i] == im.merge_field) cur = i + 1;
                }
                choice (g, _("Merge Field"), fields, cur, (v) => im.merge_field = v == 0 ? "" : pub.merge.fields[(int) v - 1]);
            }
        }

        private void build_table (TableItem t) {
            var g = group (_("Table"), _("%d rows, %d columns").printf (t.rows, t.cols));
            var rows = tool_row (g, _("Rows"));
            tool (rows, "list-add-symbolic", "list-add-symbolic", _("Insert Row Above"), "win.table-row-above");
            tool (rows, "go-down-symbolic", "go-down-symbolic", _("Insert Row Below"), "win.table-row-below");
            tool (rows, "list-remove-symbolic", "list-remove-symbolic", _("Delete Row"), "win.table-row-delete");
            var cols = tool_row (g, _("Columns"));
            tool (cols, "list-add-symbolic", "list-add-symbolic", _("Insert Column Left"), "win.table-col-left");
            tool (cols, "go-next-symbolic", "go-next-symbolic", _("Insert Column Right"), "win.table-col-right");
            tool (cols, "list-remove-symbolic", "list-remove-symbolic", _("Delete Column"), "win.table-col-delete");
            var cells = tool_row (g, _("Cells"));
            tool (cells, "view-app-grid-symbolic", "view-app-grid-symbolic", _("Merge Cells"), "win.table-merge");
            tool (cells, "view-grid-symbolic", "view-grid-symbolic", _("Split Cell"), "win.table-split");
            tool (cells, "view-continuous-symbolic", "view-continuous-symbolic", _("Distribute Rows and Columns"), "win.table-distribute");
            string[] tstyles = { _("None") };
            int tcur = 0;
            for (int i = 0; i < pub.table_styles.size; i++) {
                tstyles += pub.table_styles[i].name;
                if (pub.table_styles[i].name == t.table_style) tcur = i + 1;
            }
            if (pub.table_styles.size > 0) choice (g, _("Table Style"), tstyles, tcur, (v) => {
                TableStyles.apply_table (pub, t, v == 0 ? "" : pub.table_styles[(int) v - 1].name);
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            spin (g, _("Header Rows"), 0, t.rows, 1, t.header_rows, 0, (v) => t.header_rows = (int) v, "hdr");
            color_row (g, _("Header Fill"), t.header_fill, true, (s) => t.header_fill = s);
            color_row (g, _("Alternating Fill"), t.alt_fill, true, (s) => t.alt_fill = s);
            color_row (g, _("Border Colour"), t.border_color, true, (s) => t.border_color = s);
            spin (g, _("Border Weight (pt)"), 0, 20, 0.25, t.border_width, 2, (v) => t.border_width = v, "tb-bw");
            len (g, _("Cell Inset"), t.cell_inset, (v) => t.cell_inset = double.max (0, v), "tb-inset", 0);
            if (canvas.cell_r1 >= 0) {
                int r1 = int.min (canvas.cell_r1, canvas.cell_r2), r2 = int.max (canvas.cell_r1, canvas.cell_r2);
                int c1 = int.min (canvas.cell_c1, canvas.cell_c2), c2 = int.max (canvas.cell_c1, canvas.cell_c2);
                var cg = group (_("Selected Cells"));
                if (pub.cell_styles.size > 0) {
                    string[] cstyles = { _("From Table Style") };
                    int ccur = 0;
                    for (int i = 0; i < pub.cell_styles.size; i++) {
                        cstyles += pub.cell_styles[i].name;
                        if (pub.cell_styles[i].name == t.cells[r1][c1].cell_style) ccur = i + 1;
                    }
                    choice (cg, _("Cell Style"), cstyles, ccur, (v) => {
                        for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) TableStyles.apply_cell (pub, t.cells[r][c], v == 0 ? "" : pub.cell_styles[(int) v - 1].name);
                    });
                }
                color_row (cg, _("Cell Fill"), t.cells[r1][c1].fill, true, (s) => {
                    for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) t.cells[r][c].fill = s;
                });
                string[] va = { _("Top"), _("Center"), _("Bottom") };
                choice (cg, _("Vertical Alignment"), va, t.cells[r1][c1].valign, (v) => {
                    for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) t.cells[r][c].valign = (int) v;
                });
                len (cg, _("Row Height"), t.row_h[r1], (v) => {
                    for (int r = r1; r <= r2; r++) t.row_h[r] = double.max (4, v);
                    double h = 0;
                    foreach (var x in t.row_h) h += x;
                    t.h = h;
                }, "row-h", 4);
                len (cg, _("Column Width"), t.col_w[c1], (v) => {
                    for (int c = c1; c <= c2; c++) t.col_w[c] = double.max (4, v);
                    double w = 0;
                    foreach (var x in t.col_w) w += x;
                    t.w = w;
                }, "col-w", 4);
            }
        }

        private void build_frame_options (TextFrame t) {
            var g = group (_("Text Frame"));
            spin (g, _("Columns"), 1, 12, 1, t.columns, 0, (v) => t.columns = (int) v, "cols");
            len (g, _("Gutter"), t.gutter, (v) => t.gutter = double.max (0, v), "gutter", 0);
            len (g, _("Inset Top"), t.inset_top, (v) => t.inset_top = v, "in-t", 0);
            len (g, _("Inset Bottom"), t.inset_bottom, (v) => t.inset_bottom = v, "in-b", 0);
            len (g, _("Inset Left"), t.inset_left, (v) => t.inset_left = v, "in-l", 0);
            len (g, _("Inset Right"), t.inset_right, (v) => t.inset_right = v, "in-r", 0);
            string[] va = { _("Top"), _("Center"), _("Bottom"), _("Justify") };
            choice (g, _("Vertical Alignment"), va, t.valign, (v) => t.valign = (int) v);
            toggle (g, _("Auto Height"), _("Grow and shrink the frame to fit its text"), t.auto_height, (v) => t.auto_height = v);
            toggle (g, _("Ignore Text Wrap"), null, t.ignore_wrap, (v) => t.ignore_wrap = v);
            var st = pub.story (t.story);
            int idx = st.frames.index_of (t.id);
            string thread = st.frames.size > 1 ? _("Frame %d of %d in this story").printf (idx + 1, st.frames.size) : _("Not threaded");
            var res = win.canvas.cache.story (t.story);
            if (res.overset) thread += ", " + ngettext ("%d character overset", "%d characters overset", res.overset_chars).printf (res.overset_chars);
            var th = new ActionRow (_("Threading"), thread);
            var b = new Button.with_label (_("Continue…"));
            b.valign = Align.CENTER;
            b.tooltip_text = _("Thread the story into another frame");
            b.clicked.connect (() => win.run ("thread-new"));
            th.add_suffix (b);
            g.add_row (th);
            if (st.frames.size > 1) button_row (g, _("Unthread"), _("Break the thread after this frame"), _("Unthread"), () => win.run ("unthread"));
            if (res.overset) button_row (g, _("Fit Frame to Text"), null, _("Fit"), () => win.run ("fit-frame"));
            ProInspector.frame_extras (this, g, t, res);
        }

        private static string[] font_families () {
            var fm = Pango.CairoFontMap.get_default ();
            Pango.FontFamily[] fams;
            fm.list_families (out fams);
            var names = new Gee.ArrayList<string> ();
            foreach (var f in fams) names.add (f.get_name ());
            names.sort ((a, b) => a.collate (b));
            return names.to_array ();
        }

        private void build_text_formatting () {
            if (win.target_stories ().size == 0 && canvas.edit == null) return;
            var cf = win.current_chars ();
            var pf = win.current_para_format ();
            var para = win.current_paragraph ();
            var sg = group (_("Styles"));
            string[] pnames = new string[pub.styles.paragraph.size];
            int pcur = 0;
            for (int i = 0; i < pub.styles.paragraph.size; i++) {
                pnames[i] = pub.styles.paragraph[i].name;
                if (para != null && pub.styles.paragraph[i].name == para.style) pcur = i;
            }
            var prow = new SelectionRow (_("Paragraph Style"), pnames, pnames.length > 0 ? pnames[pcur] : "");
            prow.selected.connect ((item) => {
                if (syncing) return;
                win.format_paras (_("Paragraph Style"), (p) => p.style = item);
            });
            sg.add_row (prow);
            string[] cnames = { _("None") };
            foreach (var c in pub.styles.character) cnames += c.name;
            var crow = new SelectionRow (_("Character Style"), cnames, cnames[0]);
            crow.selected.connect ((item) => {
                if (syncing) return;
                string v = item == _("None") ? "" : item;
                win.format_runs (_("Character Style"), (r) => r.cstyle = v);
            });
            sg.add_row (crow);
            var cg = group (_("Character"));
            var fams = font_families ();
            var fam_row = new ActionRow (_("Font"));
            var model = new StringList (null);
            foreach (string f in fams) model.append (f);
            var expr = new PropertyExpression (typeof (StringObject), null, "string");
            var dd = new DropDown (model, expr);
            dd.enable_search = true;
            dd.valign = Align.CENTER;
            dd.set_size_request (170, -1);
            for (int i = 0; i < fams.length; i++) if (fams[i] == cf.font) dd.selected = i;
            dd.notify["selected"].connect (() => {
                if (syncing || dd.selected >= fams.length) return;
                string f = fams[dd.selected];
                win.format_runs (_("Font"), (r) => r.fmt.font = f);
            });
            fam_row.add_suffix (dd);
            cg.add_row (fam_row);
            if (!Preflight.system_has_font (cf.font ?? "")) cg.add_row (new ActionRow (_("Missing Font"), _("\"%s\" is not installed; a substitute is shown").printf (cf.font)));
            var size_row = new SpinRow (_("Size (pt)"), null, 1, 1296, 0.5, cf.size);
            size_row.spin_btn.digits = 1;
            size_row.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = size_row.spin_btn.value;
                win.format_runs (_("Font Size"), (r) => r.fmt.size = v, "size");
            });
            cg.add_row (size_row);
            var box = tool_row (cg, _("Style"));
            var bold = tool (box, "format-text-bold-symbolic", "format-text-bold-symbolic", _("Bold (Ctrl+B)"), "win.bold");
            if (cf.bold == 1) bold.add_css_class ("suggested-action");
            var ital = tool (box, "format-text-italic-symbolic", "format-text-italic-symbolic", _("Italic (Ctrl+Shift+I)"), "win.italic");
            if (cf.italic == 1) ital.add_css_class ("suggested-action");
            var und = tool (box, "format-text-underline-symbolic", "format-text-underline-symbolic", _("Underline (Ctrl+U)"), "win.underline");
            if (cf.underline == 1) und.add_css_class ("suggested-action");
            var str = tool (box, "format-text-strikethrough-symbolic", "format-text-strikethrough-symbolic", _("Strikethrough"), "win.strike");
            if (cf.strike == 1) str.add_css_class ("suggested-action");
            var colb = new ActionRow (_("Colour"));
            var sb = new SwatchButton (win, cf.color ?? ColorRef.BLACK, false);
            sb.chosen.connect ((s) => win.format_runs (_("Text Colour"), (r) => r.fmt.color = s));
            colb.add_suffix (sb);
            cg.add_row (colb);
            var tr = new SpinRow (_("Tracking (1/1000 em)"), null, -500, 2000, 5, cf.tracking.is_nan () ? 0 : cf.tracking);
            tr.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = tr.spin_btn.value;
                win.format_runs (_("Tracking"), (r) => r.fmt.tracking = v, "tracking");
            });
            cg.add_row (tr);
            var bs = new SpinRow (_("Baseline Shift (pt)"), null, -200, 200, 0.5, cf.baseline_shift.is_nan () ? 0 : cf.baseline_shift);
            bs.spin_btn.digits = 1;
            bs.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = bs.spin_btn.value;
                win.format_runs (_("Baseline Shift"), (r) => r.fmt.baseline_shift = v, "shift");
            });
            cg.add_row (bs);
            string[] caps = { _("Normal"), _("All Caps"), _("Small Caps") };
            var capr = new SelectionRow (_("Case"), caps, caps[cf.caps.clamp (0, 2)]);
            capr.selected.connect ((item) => {
                if (syncing) return;
                int v = 0;
                for (int i = 0; i < caps.length; i++) if (caps[i] == item) v = i;
                win.format_runs (_("Case"), (r) => r.fmt.caps = v);
            });
            cg.add_row (capr);
            string[] pos = { _("Normal"), _("Superscript"), _("Subscript") };
            var posr = new SelectionRow (_("Position"), pos, pos[cf.position.clamp (0, 2)]);
            posr.selected.connect ((item) => {
                if (syncing) return;
                int v = 0;
                for (int i = 0; i < pos.length; i++) if (pos[i] == item) v = i;
                win.format_runs (_("Position"), (r) => r.fmt.position = v);
            });
            cg.add_row (posr);
            ProInspector.text_effects (this, cf);
            var og = group (_("OpenType"), _("Features the font provides, applied through Pango"));
            var kern = new SwitchRow (_("Kerning"), null, cf.kerning != 0);
            kern.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = kern.switch_btn.active ? 1 : 0;
                win.format_runs (_("Kerning"), (r) => r.fmt.kerning = v);
            });
            og.add_row (kern);
            var lig = new SwitchRow (_("Ligatures"), null, cf.ligatures != 0);
            lig.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = lig.switch_btn.active ? 1 : 0;
                win.format_runs (_("Ligatures"), (r) => r.fmt.ligatures = v);
            });
            og.add_row (lig);
            string feats = cf.features ?? "";
            string[,] opts = { { _("Oldstyle Figures"), "onum" }, { _("Tabular Figures"), "tnum" }, { _("Small Caps from Font"), "smcp" }, { _("Discretionary Ligatures"), "dlig" }, { _("Fractions"), "frac" }, { _("Stylistic Set 1"), "ss01" }, { _("Swashes"), "swsh" }, { _("Slashed Zero"), "zero" } };
            for (int i = 0; i < opts.length[0]; i++) {
                string tag = opts[i, 1];
                bool on = feats.contains (tag + "=1") || feats.contains (tag + " 1");
                var fr = new SwitchRow (opts[i, 0], null, on);
                fr.switch_btn.notify["active"].connect (() => {
                    if (syncing) return;
                    bool v = fr.switch_btn.active;
                    win.format_runs (_("OpenType Feature"), (r) => r.fmt.features = toggle_feature (r.fmt.features ?? win.current_chars ().features ?? "", tag, v));
                });
                og.add_row (fr);
            }
            var lang = new EntryRow (_("Language"));
            lang.text = cf.lang ?? "en";
            lang.entry_activated.connect (() => {
                string v = lang.text.strip ();
                win.format_runs (_("Language"), (r) => r.fmt.lang = v);
            });
            og.add_row (lang);
            var axes = FontAxes.for_family (cf.font ?? "");
            if (axes.size > 0) {
                var vg = group (_("Variable Font"), _("Axes of %s").printf (cf.font));
                var cur = FontAxes.values (cf.variations);
                foreach (var ax in axes) {
                    var axis = ax;
                    double v = cur.has_key (axis.tag) ? cur[axis.tag] : axis.def;
                    var row = new SpinRow (axis.label (), "%s, %g to %g".printf (axis.tag, axis.min, axis.max), axis.min, axis.max, axis.max - axis.min > 20 ? 1 : 0.1, v);
                    row.spin_btn.digits = axis.max - axis.min > 20 ? 0 : 1;
                    row.spin_btn.value_changed.connect (() => {
                        if (syncing) return;
                        double nv = row.spin_btn.value;
                        win.format_runs (_("Font Axis"), (r) => {
                            var map = FontAxes.values (r.fmt.variations ?? win.current_chars ().variations);
                            map[axis.tag] = nv;
                            r.fmt.variations = FontAxes.join (map);
                        });
                    });
                    vg.add_row (row);
                }
            }
            var pg = group (_("Paragraph"));
            var abox = tool_row (pg, _("Alignment"));
            tool (abox, "format-justify-left-symbolic", "format-justify-left-symbolic", _("Align Left"), "win.align-left");
            tool (abox, "format-justify-center-symbolic", "format-justify-center-symbolic", _("Align Center"), "win.align-center");
            tool (abox, "format-justify-right-symbolic", "format-justify-right-symbolic", _("Align Right"), "win.align-right");
            tool (abox, "format-justify-fill-symbolic", "format-justify-fill-symbolic", _("Justify"), "win.align-justify");
            para_len (pg, _("Left Indent"), pf.left_indent, (p, v) => p.fmt.left_indent = v, "li");
            para_len (pg, _("First Line Indent"), pf.first_indent, (p, v) => p.fmt.first_indent = v, "fi");
            para_len (pg, _("Right Indent"), pf.right_indent, (p, v) => p.fmt.right_indent = v, "ri");
            para_len (pg, _("Space Before"), pf.space_before, (p, v) => p.fmt.space_before = v, "sb");
            para_len (pg, _("Space After"), pf.space_after, (p, v) => p.fmt.space_after = v, "sa");
            var lead = new SpinRow (_("Leading (pt, 0 is auto)"), null, 0, 1000, 0.5, pf.leading);
            lead.spin_btn.digits = 1;
            lead.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = lead.spin_btn.value;
                win.format_paras (_("Leading"), (p) => p.fmt.leading = v, "leading");
            });
            pg.add_row (lead);
            var grid = new SwitchRow (_("Align to Baseline Grid"), null, pf.align_grid == 1);
            grid.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = grid.switch_btn.active ? 1 : 0;
                win.format_paras (_("Align to Baseline Grid"), (p) => p.fmt.align_grid = v);
            });
            pg.add_row (grid);
            var hyp = new SwitchRow (_("Hyphenate"), Hyphenator.describe (cf.lang ?? "en"), pf.hyphenate == 1);
            hyp.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = hyp.switch_btn.active ? 1 : 0;
                win.format_paras (_("Hyphenation"), (p) => p.fmt.hyphenate = v);
            });
            pg.add_row (hyp);
            var keep_n = new SwitchRow (_("Keep with Next"), null, pf.keep_next == 1);
            keep_n.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = keep_n.switch_btn.active ? 1 : 0;
                win.format_paras (_("Keep with Next"), (p) => p.fmt.keep_next = v);
            });
            pg.add_row (keep_n);
            var optical = new SwitchRow (_("Optical Margin Alignment"), _("Punctuation and round letters hang slightly into the margin"), pf.optical == 1);
            optical.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = optical.switch_btn.active ? 1 : 0;
                win.format_paras (_("Optical Margin Alignment"), (p) => p.fmt.optical = v);
            });
            pg.add_row (optical);
            string[] dirs = { _("Left to Right"), _("Right to Left") };
            var dir = new SelectionRow (_("Paragraph Direction"), dirs, dirs[pf.direction == 1 ? 1 : 0]);
            dir.subtitle = _("Arabic, Hebrew and other right-to-left scripts");
            dir.selected.connect ((v) => {
                if (syncing) return;
                int d = v == dirs[1] ? 1 : 0;
                win.format_paras (_("Paragraph Direction"), (p) => p.fmt.direction = d);
            });
            pg.add_row (dir);
            var keep_l = new SwitchRow (_("Keep Lines Together"), null, pf.keep_lines == 1);
            keep_l.switch_btn.notify["active"].connect (() => {
                if (syncing) return;
                int v = keep_l.switch_btn.active ? 1 : 0;
                win.format_paras (_("Keep Lines Together"), (p) => p.fmt.keep_lines = v);
            });
            pg.add_row (keep_l);
            var dg = group (_("Drop Cap"));
            var dl = new SpinRow (_("Lines"), null, 0, 12, 1, pf.drop_lines);
            dl.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                int v = (int) dl.spin_btn.value;
                win.format_paras (_("Drop Cap"), (p) => p.fmt.drop_lines = v, "drop-l");
            });
            dg.add_row (dl);
            var dc = new SpinRow (_("Characters"), null, 1, 20, 1, pf.drop_chars);
            dc.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                int v = (int) dc.spin_btn.value;
                win.format_paras (_("Drop Cap"), (p) => p.fmt.drop_chars = v, "drop-c");
            });
            dg.add_row (dc);
            var lg = group (_("Bullets and Numbering"));
            string[] lt = { _("None"), _("Bullets"), _("Numbers") };
            var ltr = new SelectionRow (_("List"), lt, lt[pf.list_type.clamp (0, 2)]);
            ltr.selected.connect ((item) => {
                if (syncing) return;
                int v = 0;
                for (int i = 0; i < lt.length; i++) if (lt[i] == item) v = i;
                win.format_paras (_("List"), (p) => {
                    p.fmt.list_type = v;
                    if (v > 0 && win.current_para_format ().left_indent < 1) {
                        p.fmt.left_indent = 18;
                        p.fmt.first_indent = -14;
                    }
                });
            });
            lg.add_row (ltr);
            if (pf.list_type == 1) {
                var bu = new EntryRow (_("Bullet Character"));
                bu.text = pf.bullet ?? "•";
                bu.entry_activated.connect (() => {
                    string v = bu.text.strip ();
                    if (v != "") win.format_paras (_("Bullet"), (p) => p.fmt.bullet = v);
                });
                lg.add_row (bu);
            } else if (pf.list_type == 2) {
                string[] nf = { "1.", "1)", "a.", "A.", "i.", "I." };
                var nfr = new SelectionRow (_("Number Format"), nf, nf[pf.number_format.clamp (0, 5)]);
                nfr.selected.connect ((item) => {
                    if (syncing) return;
                    int v = 0;
                    for (int i = 0; i < nf.length; i++) if (nf[i] == item) v = i;
                    win.format_paras (_("Number Format"), (p) => p.fmt.number_format = v);
                });
                lg.add_row (nfr);
                var ns = new SpinRow (_("Restart At"), null, 0, 9999, 1, para != null && para.fmt.number_start >= 0 ? para.fmt.number_start : 0);
                ns.spin_btn.value_changed.connect (() => {
                    if (syncing) return;
                    int v = (int) ns.spin_btn.value;
                    win.format_paras (_("Restart Numbering"), (p) => p.fmt.number_start = v > 0 ? v : -1, "num-start");
                });
                lg.add_row (ns);
                var lvl = new SpinRow (_("Level"), null, 1, 9, 1, pf.list_level + 1);
                lvl.spin_btn.value_changed.connect (() => {
                    if (syncing) return;
                    int v = (int) lvl.spin_btn.value - 1;
                    win.format_paras (_("List Level"), (p) => p.fmt.list_level = v, "lvl");
                });
                lg.add_row (lvl);
            }
            var tg = group (_("Tabs"), _("Positions from the left edge of the column"));
            var tabs = TabStop.parse (pf.tabs);
            for (int i = 0; i < tabs.size; i++) {
                var t = tabs[i];
                int idx = i;
                string[] kinds = { _("Left"), _("Center"), _("Right"), _("Decimal") };
                string lead_txt = t.leader != "" ? _(", leader \"%s\"").printf (t.leader) : "";
                var tr2 = new ActionRow ("%s %s".printf (kinds[(int) t.kind], Units.format (t.pos, unit)), lead_txt != "" ? lead_txt.substring (2) : null);
                var rm = new Button.from_icon_name ("list-remove-symbolic");
                rm.add_css_class ("flat");
                rm.valign = Align.CENTER;
                rm.tooltip_text = _("Remove Tab");
                rm.clicked.connect (() => {
                    var l = TabStop.parse (win.current_para_format ().tabs);
                    if (idx < l.size) l.remove_at (idx);
                    string s = TabStop.serialize (l);
                    win.format_paras (_("Tabs"), (p) => p.fmt.tabs = s);
                });
                tr2.add_suffix (rm);
                tg.add_row (tr2);
            }
            button_row (tg, _("Add Tab Stop"), null, _("Add…"), () => Dialogs.add_tab (win));
        }

        private static string toggle_feature (string feats, string tag, bool on) {
            var parts = new Gee.ArrayList<string> ();
            foreach (string p in feats.split (",")) {
                string t = p.strip ();
                if (t == "" || t.has_prefix (tag)) continue;
                parts.add (t);
            }
            if (on) parts.add (tag + "=1");
            return string.joinv (", ", parts.to_array ());
        }

        private delegate void ParaLenApply (Paragraph p, double v);

        private void para_len (PreferencesGroup g, string title, double pt, owned ParaLenApply apply, string key) {
            string u = unit;
            double f = Units.factor (u);
            var row = new SpinRow ("%s (%s)".printf (title, u), null, -10000, 10000, u == "in" ? 0.0625 : 1, Math.round (pt / f * 100) / 100);
            row.spin_btn.digits = 2;
            row.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = row.spin_btn.value * f;
                win.format_paras (title, (p) => apply (p, v), key);
            });
            g.add_row (row);
        }
    }
}
