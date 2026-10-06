using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class ProInspector {
        private static int index_of (string[] ids, string id) {
            for (int i = 0; i < ids.length; i++) if (ids[i] == id) return i;
            return 0;
        }

        private static void later (Inspector ins) {
            Idle.add (() => {
                ins.rebuild ();
                return Source.REMOVE;
            });
        }

        public static void fill_extras (Inspector ins, PreferencesGroup g, Item it) {
            var f = it.fill;
            switch (f.kind) {
                case FillKind.PATTERN:
                    string[] ids = FxRender.pattern_ids ();
                    string[] labels = new string[ids.length];
                    for (int i = 0; i < ids.length; i++) labels[i] = FxRender.pattern_label (ids[i]);
                    ins.choice (g, _("Pattern"), labels, index_of (ids, f.pattern), (v) => it.fill.pattern = ids[(int) v]);
                    ins.color_row (g, _("Foreground"), f.color, false, (s) => it.fill.color = s);
                    ins.color_row (g, _("Background"), f.bg_color, true, (s) => it.fill.bg_color = s);
                    ins.spin (g, _("Pattern Scale %"), 25, 800, 25, Math.round (f.tile_scale * 100), 0, (v) => it.fill.tile_scale = v / 100, "pat-scale");
                    break;
                case FillKind.TEXTURE:
                    string[] tids = FxRender.texture_ids ();
                    string[] tl = new string[tids.length];
                    for (int i = 0; i < tids.length; i++) tl[i] = FxRender.texture_label (tids[i]);
                    ins.choice (g, _("Texture"), tl, index_of (tids, f.texture), (v) => it.fill.texture = tids[(int) v]);
                    ins.spin (g, _("Texture Scale %"), 10, 800, 10, Math.round (f.tile_scale * 100), 0, (v) => it.fill.tile_scale = v / 100, "tex-scale");
                    break;
                case FillKind.PICTURE:
                    string sub = f.link != "" ? Path.get_basename (f.link) : (f.media != "" ? _("Embedded picture") : _("No picture chosen"));
                    ins.button_row (g, _("Picture"), sub, _("Choose…"), () => ProDialogs.choose_fill_picture.begin (ins.win, it));
                    ins.toggle (g, _("Tile Picture"), null, f.tile, (v) => it.fill.tile = v);
                    if (f.tile) ins.spin (g, _("Tile Scale %"), 5, 800, 5, Math.round (f.tile_scale * 100), 0, (v) => it.fill.tile_scale = v / 100, "pic-scale");
                    break;
                default:
                    break;
            }
        }

        public static void effects (Inspector ins, Item it) {
            var g = ins.group (_("Effects"));
            var e = it.effects;
            ins.toggle (g, _("Glow"), null, e.glow, (v) => {
                it.effects.glow = v;
                later (ins);
            });
            if (e.glow) {
                ins.spin (g, _("Glow Size (pt)"), 1, 60, 1, e.glow_size, 0, (v) => it.effects.glow_size = v, "glow-size");
                ins.spin (g, _("Glow Opacity %"), 5, 100, 5, Math.round (e.glow_opacity * 100), 0, (v) => it.effects.glow_opacity = v / 100, "glow-op");
                ins.color_row (g, _("Glow Colour"), e.glow_color, false, (s) => it.effects.glow_color = s);
            }
            ins.spin (g, _("Soft Edges (pt)"), 0, 60, 1, e.soft_edges, 0, (v) => it.effects.soft_edges = v, "soft");
            ins.toggle (g, _("Reflection"), null, e.reflection, (v) => {
                it.effects.reflection = v;
                later (ins);
            });
            if (e.reflection) {
                ins.spin (g, _("Reflection Size %"), 5, 100, 5, Math.round (e.reflection_size * 100), 0, (v) => it.effects.reflection_size = v / 100, "refl-size");
                ins.spin (g, _("Reflection Transparency %"), 0, 100, 5, Math.round ((1 - e.reflection_opacity) * 100), 0, (v) => it.effects.reflection_opacity = 1 - v / 100, "refl-op");
                ins.spin (g, _("Reflection Distance (pt)"), 0, 50, 1, e.reflection_distance, 0, (v) => it.effects.reflection_distance = v, "refl-d");
            }
            ins.toggle (g, _("Bevel"), null, e.bevel, (v) => {
                it.effects.bevel = v;
                later (ins);
            });
            if (e.bevel) ins.spin (g, _("Bevel Depth (pt)"), 1, 40, 1, e.bevel_depth, 0, (v) => it.effects.bevel_depth = v, "bevel");
            if (it is GroupItem) return;
            string[] ids = FxRender.border_ids ();
            string[] labels = new string[ids.length + 1];
            labels[0] = _("None");
            for (int i = 0; i < ids.length; i++) labels[i + 1] = FxRender.border_label (ids[i]);
            int cur = it.border_art.design == "" ? 0 : index_of (ids, it.border_art.design) + 1;
            var bg = ins.group (_("BorderArt"));
            ins.choice (bg, _("Border"), labels, cur, (v) => {
                it.border_art.design = v == 0 ? "" : ids[(int) v - 1];
                later (ins);
            });
            if (it.border_art.design != "") {
                ins.spin (bg, _("Border Size (pt)"), 4, 72, 1, it.border_art.size, 0, (v) => it.border_art.size = v, "ba-size");
                ins.color_row (bg, _("Border Colour"), it.border_art.color, true, (s) => it.border_art.color = s);
            }
            ins.button_row (bg, _("Browse Borders"), null, _("Browse…"), () => ProDialogs.border_art (ins.win));
        }

        public static void wrap_extras (Inspector ins, PreferencesGroup g, Item it) {
            bool editing = ins.canvas.wrap_item == it;
            if (!it.wrap.wraps () && !editing) return;
            ins.button_row (g, _("Wrap Points"), it.wrap_points.size >= 3 ? ngettext ("%d custom point", "%d custom points", it.wrap_points.size).printf (it.wrap_points.size) : _("Follows the object outline"), editing ? _("Done") : _("Edit"), () => ins.win.run ("edit-wrap-points"));
            if (it.wrap_points.size >= 3) ins.button_row (g, _("Reset Wrap Points"), null, _("Reset"), () => ins.win.run ("reset-wrap-points"));
        }

        public static void object_extras (Inspector ins, Item it) {
            var g = ins.group (_("Accessibility and Links"));
            string alt = it.alt_decorative ? _("Decorative") : (it.alt_text != "" ? it.alt_text : _("None"));
            if (alt.char_count () > 40) alt = alt.substring (0, alt.index_of_nth_char (40)) + "…";
            ins.button_row (g, _("Alternative Text"), alt, _("Edit…"), () => ins.win.run ("alt-text"));
            string link = it.link != "" ? ProDialogs.link_label (ins.pub, it.link) : _("None");
            ins.button_row (g, _("Hyperlink"), link, _("Edit…"), () => ins.win.run ("insert-hyperlink"));
            var pg = ins.group (_("Commercial Print"));
            ins.toggle (pg, _("Overprint Fill"), _("The fill prints over the inks below instead of knocking them out"), it.overprint_fill, (v) => it.overprint_fill = v);
            ins.toggle (pg, _("Overprint Stroke"), null, it.overprint_stroke, (v) => it.overprint_stroke = v);
        }

        public static void multi (Inspector ins, Gee.List<Item> sel) {
            int images = 0;
            foreach (var it in sel) if (it is ImageFrame) images++;
            if (images == 2 && sel.size == 2) {
                var g = ins.group (_("Pictures"));
                ins.button_row (g, _("Swap Pictures"), _("Exchange the two pictures and keep their frames"), _("Swap"), () => ins.win.run ("swap-pictures"));
            }
        }

        public static void image (Inspector ins, ImageFrame im) {
            var g = ins.group (_("Corrections"));
            ins.spin (g, _("Brightness %"), -100, 100, 5, Math.round (im.brightness * 100), 0, (v) => im.brightness = v / 100, "img-bright");
            ins.spin (g, _("Contrast %"), -100, 100, 5, Math.round (im.contrast * 100), 0, (v) => im.contrast = v / 100, "img-contrast");
            ins.choice (g, _("Recolour"), FxRender.recolor_labels (), im.recolor, (v) => {
                im.recolor = (int) v;
                later (ins);
            });
            if (im.recolor == 5) ins.color_row (g, _("Recolour With"), im.recolor_color, false, (s) => im.recolor_color = s);
            var tr = new EntryRow (_("Transparent Colour"));
            tr.text = im.transparent_color;
            tr.tooltip_text = _("A colour such as #ffffff that becomes transparent");
            tr.entry_activated.connect (() => {
                string v = tr.text.strip ();
                Rgba c;
                if (v != "" && !Rgba.parse_hex (v, out c)) return;
                ins.edit (_("Transparent Colour"), () => im.transparent_color = v);
            });
            g.add_row (tr);
            ins.button_row (g, _("Reset Picture"), _("Remove corrections, recolouring and styles"), _("Reset"), () => ins.win.run ("reset-picture"));
            var sg = ins.group (_("Picture Style"));
            string[] ids = PictureStyles.ids ();
            string[] labels = new string[ids.length + 1];
            labels[0] = _("None");
            for (int i = 0; i < ids.length; i++) labels[i + 1] = PictureStyles.label (ids[i]);
            ins.choice (sg, _("Style"), labels, 0, (v) => {
                if (v == 0) PictureStyles.apply (im, "");
                else PictureStyles.apply (im, ids[(int) v - 1]);
                later (ins);
            });
            string[] shapes = ShapeLib.clip_shapes ();
            string[] sl = new string[shapes.length];
            for (int i = 0; i < shapes.length; i++) sl[i] = ShapeLib.clip_label (shapes[i]);
            ins.choice (sg, _("Crop to Shape"), sl, index_of (shapes, im.clip_shape), (v) => im.clip_shape = shapes[(int) v]);
            var cg = ins.group (_("Caption"));
            string[] cids = Captions.ids ();
            string[] cl = new string[cids.length];
            for (int i = 0; i < cids.length; i++) cl[i] = Captions.label (cids[i]);
            var row = new SelectionRow (_("Add Caption"), cl, "");
            row.selected.connect ((item) => {
                for (int i = 0; i < cl.length; i++) if (cl[i] == item) ins.win.activate_action_variant ("win.add-caption", new Variant.string (cids[i]));
            });
            cg.add_row (row);
        }

        public static void table (Inspector ins, TableItem t) {
            var g = ins.group (_("Table Format"));
            string[] ids = TableFormats.ids ();
            string[] labels = new string[ids.length];
            for (int i = 0; i < ids.length; i++) labels[i] = TableFormats.label (ids[i]);
            var row = new SelectionRow (_("Format"), labels, "");
            row.selected.connect ((item) => {
                for (int i = 0; i < labels.length; i++) if (labels[i] == item) ins.win.activate_action_variant ("win.table-format", new Variant.string (ids[i]));
            });
            g.add_row (row);
            if (ins.canvas.cell_r1 >= 0) {
                int r1 = int.min (ins.canvas.cell_r1, ins.canvas.cell_r2), c1 = int.min (ins.canvas.cell_c1, ins.canvas.cell_c2);
                string[] diags = { _("None"), _("Divide Down"), _("Divide Up") };
                ins.choice (g, _("Diagonal"), diags, t.cells[r1][c1].diagonal, (v) => {
                    int r2 = int.max (ins.canvas.cell_r1, ins.canvas.cell_r2), c2 = int.max (ins.canvas.cell_c1, ins.canvas.cell_c2);
                    for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) t.cells[r][c].diagonal = (int) v;
                });
            }
        }

        public static void wordart (Inspector ins, WordArtItem wa) {
            var g = ins.group (_("WordArt"));
            var text = new EntryRow (_("Text"));
            text.text = wa.text;
            text.entry_changed.connect (() => ins.edit (_("WordArt Text"), () => wa.text = text.text, "wa-text"));
            g.add_row (text);
            var fam = new EntryRow (_("Font"));
            fam.text = wa.font;
            fam.entry_activated.connect (() => {
                string v = fam.text.strip ();
                if (v != "") ins.edit (_("WordArt Font"), () => wa.font = v);
            });
            g.add_row (fam);
            ins.toggle (g, _("Bold"), null, wa.bold, (v) => wa.bold = v);
            ins.toggle (g, _("Italic"), null, wa.italic, (v) => wa.italic = v);
            var kinds = WarpKind.all ();
            string[] labels = new string[kinds.length];
            int cur = 0;
            for (int i = 0; i < kinds.length; i++) {
                labels[i] = kinds[i].label ();
                if (kinds[i] == wa.warp) cur = i;
            }
            ins.choice (g, _("Shape"), labels, cur, (v) => wa.warp = kinds[(int) v]);
            ins.spin (g, _("Shape Amount %"), 0, 100, 5, Math.round (wa.warp_amount * 100), 0, (v) => wa.warp_amount = v / 100, "wa-amount");
            ins.button_row (g, _("WordArt Gallery"), null, _("Choose…"), () => ProDialogs.wordart (ins.win, wa));
        }

        public static void frame_extras (Inspector ins, PreferencesGroup g, TextFrame t, StoryResult res) {
            string[] fits = { _("Do Not Autofit"), _("Shrink Text on Overflow"), _("Best Fit") };
            ins.choice (g, _("Text Fit"), fits, t.autofit.clamp (0, 2), (v) => {
                t.autofit = (int) v;
                if (v != 0) t.auto_height = false;
            });
            if (t.autofit != 0 && res.scale != 1) g.add_row (new ActionRow (_("Text Scale"), "%d%%".printf ((int) Math.round (res.scale * 100))));
            ins.toggle (g, _("Rotate Text 90°"), _("Text reads from top to bottom"), t.vertical, (v) => t.vertical = v);
            ins.toggle (g, _("Own Baseline Grid"), _("Paragraphs aligned to the grid use this frame's grid"), t.own_grid, (v) => t.own_grid = v);
            if (t.own_grid) {
                ins.spin (g, _("Grid Start (pt)"), 0, 1000, 1, t.grid_start, 1, (v) => t.grid_start = v, "grid-start");
                ins.spin (g, _("Grid Increment (pt)"), 1, 200, 0.5, t.grid_step, 1, (v) => t.grid_step = v, "grid-step");
            }
            if (res.overset) ins.button_row (g, _("Autoflow"), _("Add pages with linked frames until the story fits"), _("Autoflow"), () => ins.win.run ("autoflow"));
        }

        public static void text_effects (Inspector ins, CharFormat cf) {
            var w = ins.win;
            var g = ins.group (_("Text Effects"));
            bool outline = cf.outline_color != null && cf.outline_color != "" && cf.outline_width > 0;
            var ol = new SwitchRow (_("Outline"), null, outline);
            ol.switch_btn.notify["active"].connect (() => {
                if (ins.syncing) return;
                bool on = ol.switch_btn.active;
                w.format_runs (_("Outline"), (r) => {
                    r.fmt.outline_color = on ? ColorRef.BLACK : "";
                    r.fmt.outline_width = on ? 0.75 : 0;
                });
            });
            g.add_row (ol);
            if (outline) {
                var row = new ActionRow (_("Outline Colour"));
                var b = new SwatchButton (w, cf.outline_color, false);
                b.chosen.connect ((s) => w.format_runs (_("Outline Colour"), (r) => r.fmt.outline_color = s));
                row.add_suffix (b);
                g.add_row (row);
                var ow = new SpinRow (_("Outline Weight (pt)"), null, 0.1, 20, 0.25, cf.outline_width);
                ow.spin_btn.digits = 2;
                ow.spin_btn.value_changed.connect (() => {
                    if (ins.syncing) return;
                    double v = ow.spin_btn.value;
                    w.format_runs (_("Outline Weight"), (r) => r.fmt.outline_width = v, "outline-w");
                });
                g.add_row (ow);
            }
            var sh = new SwitchRow (_("Shadow"), null, cf.text_shadow == 1);
            sh.switch_btn.notify["active"].connect (() => {
                if (ins.syncing) return;
                int v = sh.switch_btn.active ? 1 : 0;
                w.format_runs (_("Shadow"), (r) => r.fmt.text_shadow = v);
            });
            g.add_row (sh);
            bool glow = cf.glow_color != null && cf.glow_color != "" && cf.glow_size > 0;
            var gl = new SwitchRow (_("Glow"), null, glow);
            gl.switch_btn.notify["active"].connect (() => {
                if (ins.syncing) return;
                bool on = gl.switch_btn.active;
                w.format_runs (_("Glow"), (r) => {
                    r.fmt.glow_color = on ? "swatch:Yellow" : "";
                    r.fmt.glow_size = on ? 5 : 0;
                });
            });
            g.add_row (gl);
            if (glow) {
                var row = new ActionRow (_("Glow Colour"));
                var b = new SwatchButton (w, cf.glow_color, false);
                b.chosen.connect ((s) => w.format_runs (_("Glow Colour"), (r) => r.fmt.glow_color = s));
                row.add_suffix (b);
                g.add_row (row);
                var gs = new SpinRow (_("Glow Size (pt)"), null, 1, 40, 1, cf.glow_size);
                gs.spin_btn.value_changed.connect (() => {
                    if (ins.syncing) return;
                    double v = gs.spin_btn.value;
                    w.format_runs (_("Glow Size"), (r) => r.fmt.glow_size = v, "glow-size");
                });
                g.add_row (gs);
            }
            var rf = new SwitchRow (_("Reflection"), null, cf.reflection == 1);
            rf.switch_btn.notify["active"].connect (() => {
                if (ins.syncing) return;
                int v = rf.switch_btn.active ? 1 : 0;
                w.format_runs (_("Reflection"), (r) => r.fmt.reflection = v);
            });
            g.add_row (rf);
            string[] emb = { _("None"), _("Emboss"), _("Engrave") };
            var er = new SelectionRow (_("Relief"), emb, emb[cf.emboss.clamp (0, 2)]);
            er.selected.connect ((item) => {
                if (ins.syncing) return;
                int v = 0;
                for (int i = 0; i < emb.length; i++) if (emb[i] == item) v = i;
                w.format_runs (_("Relief"), (r) => r.fmt.emboss = v);
            });
            g.add_row (er);
            string link = cf.link != null && cf.link != "" ? ProDialogs.link_label (ins.pub, cf.link) : _("None");
            ins.button_row (g, _("Hyperlink"), link, _("Edit…"), () => w.run ("insert-hyperlink"));
        }
    }
}
