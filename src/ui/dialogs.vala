using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class Dialogs {
        public delegate void Apply ();
        public delegate void NameFunc (string name);
        private static Gee.HashMap<string, Gdk.Texture>? thumbs = null;

        public static AppDialog make (PublishWindow win, string title, int width, int height) {
            var dlg = new AppDialog ((Gtk.Application) win.application, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, int.min (height, screen_room (win)));
            return dlg;
        }

        public static int screen_room (Gtk.Widget w) {
            var display = w.get_display ();
            Gdk.Monitor? mon = null;
            var surface = w.get_native () != null ? w.get_native ().get_surface () : null;
            if (surface != null) mon = display.get_monitor_at_surface (surface);
            if (mon == null && display.get_monitors ().get_n_items () > 0) mon = (Gdk.Monitor) display.get_monitors ().get_item (0);
            if (mon == null) return 10000;
            return int.max (320, mon.geometry.height - 120);
        }

        public static Box body (AppDialog dlg) {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            dlg.content_box.append (scroll);
            return box;
        }

        public static Button footer (AppDialog dlg, string label, owned Apply apply, bool close_after = true) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var cancel = dlg.add_cancel_button ();
            var ok = new Button.with_label (label);
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                apply ();
                if (close_after) dlg.close ();
            });
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            return ok;
        }

        private static SpinRow unit_spin (PreferencesGroup g, string title, double pt, string unit, double min = 0) {
            double f = Units.factor (unit);
            var row = new SpinRow ("%s (%s)".printf (title, unit), null, min / f, 20000 / f, unit == "in" ? 0.0625 : (unit == "pt" ? 1 : 0.5), Math.round (pt / f * 1000) / 1000);
            row.spin_btn.digits = unit == "in" ? 3 : 2;
            g.add_row (row);
            return row;
        }

        public static Gdk.Texture template_thumb (string id, int size) {
            if (thumbs == null) thumbs = new Gee.HashMap<string, Gdk.Texture> ();
            string key = "%s:%d".printf (id, size);
            if (thumbs.has_key (key)) return thumbs[key];
            var p = Templates.build (id);
            var ex = new Exporter (p);
            int px = size * 2;
            var page = ex.thumbnail (0, px - 8);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, px, px);
            var cr = new Cairo.Context (surf);
            double x = (px - page.get_width ()) / 2.0, y = (px - page.get_height ()) / 2.0;
            for (int i = 3; i >= 1; i--) {
                cr.set_source_rgba (0, 0, 0, 0.06);
                Renderer.round_rect (cr, x - i + 1, y - i + 3, page.get_width () + 2 * i - 2, page.get_height () + 2 * i - 2, 3);
                cr.fill ();
            }
            cr.set_source_surface (page, x, y);
            cr.paint ();
            cr.set_source_rgba (0, 0, 0, 0.18);
            cr.set_line_width (1);
            cr.rectangle (x + 0.5, y + 0.5, page.get_width () - 1, page.get_height () - 1);
            cr.stroke ();
            surf.flush ();
            var tex = Gdk.Texture.for_pixbuf (Exporter.surface_to_pixbuf (surf, true));
            thumbs[key] = tex;
            return tex;
        }

        public static Gtk.Widget template_card (TemplateInfo t, int width, owned Apply activate) {
            var b = new Button ();
            b.add_css_class ("flat");
            b.add_css_class ("publish-template-card");
            b.halign = Align.CENTER;
            b.valign = Align.START;
            b.tooltip_text = t.description;
            var box = new Box (Orientation.VERTICAL, 6);
            var pic = new Image.from_paintable (template_thumb (t.id, width));
            pic.pixel_size = width;
            box.append (pic);
            var name = new Label (t.name);
            name.add_css_class ("caption");
            name.add_css_class ("heading");
            name.xalign = 0;
            box.append (name);
            var cat = new Label (t.category);
            cat.add_css_class ("caption");
            cat.add_css_class ("dim-label");
            cat.xalign = 0;
            box.append (cat);
            b.child = box;
            b.clicked.connect (() => activate ());
            return b;
        }

        public static void templates (PublishWindow win) {
            var dlg = make (win, _("New from Template"), 820, 760);
            var box = body (dlg);
            var cats = new Gee.ArrayList<string> ();
            foreach (var t in Templates.all ()) if (!cats.contains (t.category)) cats.add (t.category);
            foreach (string c in cats) {
                var g = new PreferencesGroup (c);
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.NONE;
                flow.max_children_per_line = 4;
                flow.min_children_per_line = 2;
                flow.column_spacing = 12;
                flow.row_spacing = 12;
                flow.margin_top = flow.margin_bottom = flow.margin_start = flow.margin_end = 8;
                foreach (var t in Templates.all ()) {
                    if (t.category != c) continue;
                    string id = t.id;
                    flow.append (template_card (t, 160, () => {
                        win.new_from_template (id);
                        dlg.close ();
                    }));
                }
                g.add_row (flow);
                box.append (g);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            bar.append (dlg.add_cancel_button ());
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        private class SetupRows {
            public SelectionRow size;
            public SpinRow width;
            public SpinRow height;
            public SelectionRow orient;
            public SwitchRow facing;
            public SwitchRow start_left;
            public SpinRow? pages;
            public SpinRow mt;
            public SpinRow mb;
            public SpinRow mi;
            public SpinRow mo;
            public SpinRow cols;
            public SpinRow gutter;
            public SpinRow bleed;
            public SpinRow slug;
            public SpinRow bstart;
            public SpinRow bstep;
            public SelectionRow units;
            public SelectionRow color;
            public SelectionRow profile;
            public SelectionRow intent;
            public SwitchRow overprint;
            public SwitchRow proof;
            public Gee.ArrayList<IccProfileInfo> profiles;
        }

        private static SetupRows setup_rows (Box box, DocSettings s, bool with_pages, PublishWindow win) {
            var r = new SetupRows ();
            string u = s.units;
            var sizes = PageSize.all ();
            string[] names = { _("Custom") };
            string cur = _("Custom");
            foreach (var ps in sizes) {
                names += "%s, %s".printf (ps.category, ps.name);
                if (ps.id == s.page_size) cur = "%s, %s".printf (ps.category, ps.name);
            }
            var pg = new PreferencesGroup (_("Page"), _("Business cards, postcards, posters and custom sizes"));
            r.size = new SelectionRow (_("Page Size"), names, cur);
            pg.add_row (r.size);
            r.width = unit_spin (pg, _("Width"), s.width, u, 1);
            r.height = unit_spin (pg, _("Height"), s.height, u, 1);
            string[] orients = { _("Portrait"), _("Landscape") };
            r.orient = new SelectionRow (_("Orientation"), orients, s.width > s.height ? orients[1] : orients[0]);
            pg.add_row (r.orient);
            r.facing = new SwitchRow (_("Facing Pages"), _("Left and right pages in spreads, with inside and outside margins"), s.facing);
            pg.add_row (r.facing);
            r.start_left = new SwitchRow (_("Start on a Left Page"), null, s.start_left);
            pg.add_row (r.start_left);
            if (with_pages) {
                r.pages = new SpinRow (_("Pages"), null, 1, 9999, 1, win.app.get_int ("default-pages", 1));
                pg.add_row (r.pages);
            }
            box.append (pg);
            bool updating = false;
            r.size.selected.connect ((item) => {
                for (int i = 0; i < sizes.size; i++) {
                    if ("%s, %s".printf (sizes[i].category, sizes[i].name) != item) continue;
                    updating = true;
                    double f = Units.factor (u);
                    bool land = r.orient.current_value == orients[1];
                    double w = sizes[i].width, h = sizes[i].height;
                    if ((land && w < h) || (!land && w > h)) {
                        double t = w;
                        w = h;
                        h = t;
                    }
                    r.width.value = Math.round (w / f * 1000) / 1000;
                    r.height.value = Math.round (h / f * 1000) / 1000;
                    updating = false;
                }
            });
            r.orient.selected.connect ((item) => {
                bool land = item == orients[1];
                double w = r.width.value, h = r.height.value;
                if ((land && w < h) || (!land && w > h)) {
                    updating = true;
                    r.width.value = h;
                    r.height.value = w;
                    updating = false;
                }
            });
            var mg = new PreferencesGroup (_("Margins and Columns"));
            r.mt = unit_spin (mg, _("Top"), s.margin_top, u);
            r.mb = unit_spin (mg, _("Bottom"), s.margin_bottom, u);
            r.mi = unit_spin (mg, _("Inside"), s.margin_inside, u);
            r.mo = unit_spin (mg, _("Outside"), s.margin_outside, u);
            r.cols = new SpinRow (_("Columns"), null, 1, 24, 1, s.columns);
            mg.add_row (r.cols);
            r.gutter = unit_spin (mg, _("Gutter"), s.gutter, u);
            box.append (mg);
            var bg = new PreferencesGroup (_("Bleed and Slug"), _("Bleed is the area past the trim that is printed and cut off"));
            r.bleed = unit_spin (bg, _("Bleed"), s.max_bleed (), u);
            r.slug = unit_spin (bg, _("Slug"), s.slug, u);
            box.append (bg);
            var gg = new PreferencesGroup (_("Baseline Grid"));
            r.bstart = unit_spin (gg, _("Start"), s.baseline_start, u);
            r.bstep = new SpinRow (_("Increment (pt)"), null, 1, 200, 0.5, s.baseline_step);
            r.bstep.spin_btn.digits = 1;
            gg.add_row (r.bstep);
            box.append (gg);
            var og = new PreferencesGroup (_("Output"));
            var ul = new string[0];
            string ucur = "";
            foreach (string x in Units.all ()) {
                ul += Units.label (x);
                if (x == u) ucur = Units.label (x);
            }
            r.units = new SelectionRow (_("Units"), ul, ucur);
            og.add_row (r.units);
            string[] cm = { _("CMYK for Print"), _("RGB for Screen") };
            r.color = new SelectionRow (_("Colour Mode"), cm, s.cmyk ? cm[0] : cm[1]);
            og.add_row (r.color);
            box.append (og);
            var cmg = new PreferencesGroup (_("Colour Management"), _("The CMYK profile converts RGB colours and pictures for print and is embedded in PDF/X files"));
            r.profiles = ColorManager.cmyk_profiles ();
            string[] pnames = { ColorManager.GENERIC_NAME };
            string pcur = ColorManager.GENERIC_NAME;
            foreach (var pi in r.profiles) {
                pnames += pi.description;
                if (pi.path == s.icc_profile) pcur = pi.description;
            }
            r.profile = new SelectionRow (_("CMYK Profile"), pnames, pcur);
            cmg.add_row (r.profile);
            string[] intents = { _("Perceptual"), _("Relative Colorimetric"), _("Saturation"), _("Absolute Colorimetric") };
            r.intent = new SelectionRow (_("Rendering Intent"), intents, intents[s.intent.clamp (0, 3)]);
            cmg.add_row (r.intent);
            r.overprint = new SwitchRow (_("Overprint Black"), _("Solid black text and lines print over other inks, avoiding white gaps"), s.overprint_black);
            cmg.add_row (r.overprint);
            r.proof = new SwitchRow (_("Proof Colours"), _("Show colours on screen as the CMYK profile will print them"), s.proof);
            cmg.add_row (r.proof);
            box.append (cmg);
            return r;
        }

        private static DocSettings read_setup (SetupRows r, DocSettings base_s) {
            var s = base_s.clone ();
            double f = Units.factor (s.units);
            s.width = r.width.value * f;
            s.height = r.height.value * f;
            s.facing = r.facing.switch_btn.active;
            s.start_left = r.start_left.switch_btn.active;
            s.margin_top = r.mt.value * f;
            s.margin_bottom = r.mb.value * f;
            s.margin_inside = r.mi.value * f;
            s.margin_outside = r.mo.value * f;
            s.columns = (int) r.cols.value;
            s.gutter = r.gutter.value * f;
            s.set_bleed (r.bleed.value * f);
            s.slug = r.slug.value * f;
            s.baseline_start = r.bstart.value * f;
            s.baseline_step = r.bstep.value;
            foreach (string x in Units.all ()) if (Units.label (x) == r.units.current_value) s.units = x;
            s.cmyk = r.color.current_value == _("CMYK for Print");
            s.icc_profile = "";
            foreach (var pi in r.profiles) if (pi.description == r.profile.current_value) s.icc_profile = pi.path;
            string[] intents = { _("Perceptual"), _("Relative Colorimetric"), _("Saturation"), _("Absolute Colorimetric") };
            for (int i = 0; i < intents.length; i++) if (intents[i] == r.intent.current_value) s.intent = i;
            s.overprint_black = r.overprint.switch_btn.active;
            s.proof = r.proof.switch_btn.active;
            var m = PageSize.match (s.width, s.height);
            s.page_size = m != null ? m.id : "custom";
            return s;
        }

        public static void new_document (PublishWindow win) {
            var dlg = make (win, _("New Publication"), 520, 760);
            var box = body (dlg);
            var s = new DocSettings ();
            s.units = win.app.get_string ("default-units", "mm");
            var ps = PageSize.find (win.app.get_string ("default-page-size", "a4")) ?? PageSize.find ("a4");
            s.width = ps.width;
            s.height = ps.height;
            s.page_size = ps.id;
            double m = 12.7 * Units.PT_PER_MM;
            s.set_margins (m);
            s.set_bleed (win.app.get_bool ("default-bleed", true) ? 3 * Units.PT_PER_MM : 0);
            var rows = setup_rows (box, s, true, win);
            footer (dlg, _("Create"), () => {
                var ns = read_setup (rows, s);
                win.new_blank (ns, (int) rows.pages.value);
            });
            dlg.open_dialog ();
        }

        public static void document_setup (PublishWindow win) {
            var dlg = make (win, _("Document Setup"), 520, 760);
            var box = body (dlg);
            var s = win.doc.pub.settings;
            var rows = setup_rows (box, s, false, win);
            footer (dlg, _("Apply"), () => {
                var ns = read_setup (rows, s);
                win.edit (_("Document Setup"), () => win.doc.pub.settings = ns);
                win.canvas.units = ns.units;
                win.canvas.relayout ();
                win.canvas.queue_allocate ();
                win.pages_panel.load ();
                win.refresh_visible_panel ();
            });
            dlg.open_dialog ();
        }

        public static void properties (PublishWindow win) {
            var dlg = make (win, _("Properties"), 460, 480);
            var box = body (dlg);
            var m = win.doc.pub.meta;
            var g = new PreferencesGroup (_("Description"), _("Saved in the document and in exported PDFs"));
            var title = new EntryRow (_("Title"));
            title.text = m.title;
            g.add_row (title);
            var author = new EntryRow (_("Author"));
            author.text = m.author;
            g.add_row (author);
            var subject = new EntryRow (_("Subject"));
            subject.text = m.subject;
            g.add_row (subject);
            var kw = new EntryRow (_("Keywords"));
            kw.text = m.keywords;
            g.add_row (kw);
            box.append (g);
            var stats = new PreferencesGroup (_("Statistics"));
            int words = 0, frames = 0, images = 0;
            foreach (var s in win.doc.pub.stories.values) foreach (string w in s.plain_text ().split_set (" \n\t")) if (w.strip () != "") words++;
            win.doc.pub.walk ((r) => {
                if (r.item is TextFrame) frames++;
                if (r.item is ImageFrame) images++;
                return true;
            });
            stats.add_row (new ActionRow (_("Pages"), win.doc.pub.pages.size.to_string ()));
            stats.add_row (new ActionRow (_("Words"), words.to_string ()));
            stats.add_row (new ActionRow (_("Text Frames"), frames.to_string ()));
            stats.add_row (new ActionRow (_("Pictures"), images.to_string ()));
            if (m.created != "") stats.add_row (new ActionRow (_("Created"), m.created));
            if (m.modified != "") stats.add_row (new ActionRow (_("Modified"), m.modified));
            box.append (stats);
            footer (dlg, _("Save"), () => {
                win.edit (_("Properties"), () => {
                    m.title = title.text;
                    m.author = author.text;
                    m.subject = subject.text;
                    m.keywords = kw.text;
                });
                win.update_title ();
            });
            dlg.open_dialog ();
        }

        private class ExportRows {
            public EntryRow? range;
            public SwitchRow? spreads;
            public SwitchRow bleed;
            public SwitchRow crop;
            public SwitchRow bleed_marks;
            public SwitchRow reg;
            public SwitchRow bars;
            public SwitchRow info;
            public SelectionRow impose;
            public SelectionRow sheet;
            public SpinRow rows;
            public SpinRow cols;
            public SpinRow gap;
            public SwitchRow repeat;
            public SpinRow tile_scale;
            public SpinRow tile_overlap;
            public SelectionRow signature;
            public SpinRow creep;
            public SelectionRow? color_mode;
            public SwitchRow? separations;
        }

        private static ExportRows export_rows (Box box, Publication p, PublishWindow win, bool with_range) {
            var r = new ExportRows ();
            var pg = new PreferencesGroup (_("Pages"));
            if (with_range) {
                r.range = new EntryRow (_("Pages to Export"));
                r.range.text = "";
                r.range.tooltip_text = _("Leave empty for all pages, or type ranges such as 1-3, 6");
                pg.add_row (r.range);
                r.spreads = new SwitchRow (_("Spreads"), _("Export facing pages side by side"), false);
                r.spreads.sensitive = p.settings.facing;
                pg.add_row (r.spreads);
            }
            box.append (pg);
            var mg = new PreferencesGroup (_("Marks and Bleed"));
            r.bleed = new SwitchRow (_("Include Bleed"), _("Bleed of %s from the document setup").printf (Units.format (p.settings.max_bleed (), p.settings.units)), p.settings.max_bleed () > 0);
            mg.add_row (r.bleed);
            r.crop = new SwitchRow (_("Crop Marks"), null, win.app.get_bool ("export-crop-marks", p.settings.max_bleed () > 0));
            mg.add_row (r.crop);
            r.bleed_marks = new SwitchRow (_("Bleed Marks"), null, false);
            mg.add_row (r.bleed_marks);
            r.reg = new SwitchRow (_("Registration Marks"), null, false);
            mg.add_row (r.reg);
            r.bars = new SwitchRow (_("Colour Bars"), null, false);
            mg.add_row (r.bars);
            r.info = new SwitchRow (_("Page Information"), null, false);
            mg.add_row (r.info);
            box.append (mg);
            var ig = new PreferencesGroup (_("Imposition"), _("Several pages on one sheet, or a folded booklet"));
            string[] modes = { _("None"), _("Several per Sheet"), _("Booklet (Saddle Stitch)"), _("Tiled Poster"), _("Signatures (Perfect Binding)") };
            string hint = p.settings.impose;
            r.impose = new SelectionRow (_("Layout"), modes, hint.has_prefix ("nup") ? modes[1] : (hint.has_prefix ("booklet") ? modes[2] : modes[0]));
            ig.add_row (r.impose);
            string[] sheets = { "A4", "A3", "SRA3", _("US Letter"), _("Tabloid") };
            string sheet_cur = "A4";
            string[] hp = hint.split (":");
            int hc = 2, hr = 2;
            if (hp.length >= 2) {
                string[] cr = hp[1].split ("x");
                if (cr.length == 2) {
                    hc = int.parse (cr[0]);
                    hr = int.parse (cr[1]);
                }
            }
            if (hp.length >= 3) {
                switch (hp[2]) {
                    case "a3": sheet_cur = "A3"; break;
                    case "sra3": sheet_cur = "SRA3"; break;
                    case "letter": sheet_cur = _("US Letter"); break;
                    case "tabloid": sheet_cur = _("Tabloid"); break;
                }
            }
            r.sheet = new SelectionRow (_("Sheet"), sheets, sheet_cur);
            ig.add_row (r.sheet);
            r.cols = new SpinRow (_("Across"), null, 1, 20, 1, hc);
            ig.add_row (r.cols);
            r.rows = new SpinRow (_("Down"), null, 1, 20, 1, hr);
            ig.add_row (r.rows);
            r.gap = new SpinRow (_("Gap (pt)"), null, 0, 200, 1, 0);
            ig.add_row (r.gap);
            r.repeat = new SwitchRow (_("Step and Repeat"), _("Fill each sheet with copies of the same page, as for business cards"), hint.has_prefix ("nup"));
            ig.add_row (r.repeat);
            r.tile_scale = new SpinRow (_("Poster Size %"), _("Tiled Poster: size of the printed poster compared with the page"), 10, 1000, 10, 100);
            ig.add_row (r.tile_scale);
            r.tile_overlap = new SpinRow (_("Tile Overlap (pt)"), _("Tiled Poster: area repeated on neighbouring sheets for gluing"), 0, 72, 1, 18);
            ig.add_row (r.tile_overlap);
            r.signature = new SelectionRow (_("Pages per Signature"), { "4", "8", "16" }, "16");
            r.signature.subtitle = _("Signatures (Perfect Binding): folded sheets gathered and glued at the spine");
            ig.add_row (r.signature);
            r.creep = new SpinRow (_("Creep (pt)"), _("Signatures: inner pages move toward the spine"), 0, 10, 0.1, 0);
            r.creep.spin_btn.digits = 1;
            ig.add_row (r.creep);
            box.append (ig);
            return r;
        }

        private static void prepress_rows (Box box, ExportRows r, Publication p) {
            var cg = new PreferencesGroup (_("Colour and Standard"), _("CMYK and PDF/X keep exact CMYK values and spot inks, set TrimBox and BleedBox and embed the output profile %s").printf (ColorManager.for_settings (p.settings).description ()));
            string[] modes = { _("RGB for Screen and Office Printers"), _("CMYK"), "PDF/X-1a:2003", "PDF/X-3:2003", "PDF/X-4" };
            r.color_mode = new SelectionRow (_("Colour Output"), modes, p.settings.cmyk ? modes[4] : modes[0]);
            cg.add_row (r.color_mode);
            var inks = PrepressExport.plates (p);
            r.separations = new SwitchRow (_("Separations"), _("One grayscale page per ink: %s").printf (string.joinv (", ", inks.to_array ())), false);
            cg.add_row (r.separations);
            box.append (cg);
        }

        private static ExportOptions read_export (ExportRows r) {
            var o = new ExportOptions ();
            if (r.range != null) o.ranges = r.range.text;
            if (r.spreads != null) o.spreads = r.spreads.switch_btn.active;
            o.bleed = r.bleed.switch_btn.active;
            o.crop_marks = r.crop.switch_btn.active;
            o.bleed_marks = r.bleed_marks.switch_btn.active;
            o.reg_marks = r.reg.switch_btn.active;
            o.color_bars = r.bars.switch_btn.active;
            o.page_info = r.info.switch_btn.active;
            string m = r.impose.current_value;
            o.impose = m == _("Several per Sheet") ? ImposeMode.NUP : (m == _("Booklet (Saddle Stitch)") ? ImposeMode.BOOKLET : (m == _("Tiled Poster") ? ImposeMode.TILE : (m == _("Signatures (Perfect Binding)") ? ImposeMode.SIGNATURES : ImposeMode.NONE)));
            o.signature = int.parse (r.signature.current_value);
            o.creep = r.creep.value;
            o.tile_scale = r.tile_scale.value / 100;
            o.tile_overlap = r.tile_overlap.value;
            if (r.color_mode != null) {
                string[] modes = { _("RGB for Screen and Office Printers"), _("CMYK"), "PDF/X-1a:2003", "PDF/X-3:2003", "PDF/X-4" };
                for (int i = 0; i < modes.length; i++) if (modes[i] == r.color_mode.current_value) o.color_mode = (ColorMode) i;
            }
            if (r.separations != null) o.separations = r.separations.switch_btn.active;
            double sw = 210 * Units.PT_PER_MM, sh = 297 * Units.PT_PER_MM;
            switch (r.sheet.current_value) {
                case "A3":
                    sw = 297 * Units.PT_PER_MM;
                    sh = 420 * Units.PT_PER_MM;
                    break;
                case "SRA3":
                    sw = 320 * Units.PT_PER_MM;
                    sh = 450 * Units.PT_PER_MM;
                    break;
                default:
                    if (r.sheet.current_value == _("US Letter")) {
                        sw = 612;
                        sh = 792;
                    } else if (r.sheet.current_value == _("Tabloid")) {
                        sw = 792;
                        sh = 1224;
                    }
                    break;
            }
            if (o.impose == ImposeMode.BOOKLET) {
                o.sheet_w = double.max (sw, sh);
                o.sheet_h = double.min (sw, sh);
            } else {
                o.sheet_w = sw;
                o.sheet_h = sh;
            }
            o.cols = (int) r.cols.value;
            o.rows = (int) r.rows.value;
            o.gap = r.gap.value;
            o.step_repeat = r.repeat.switch_btn.active;
            return o;
        }

        public static void export_pdf (PublishWindow win, Publication? source = null, string? name = null) {
            var p = source ?? win.doc.pub;
            var dlg = make (win, _("Export PDF for Print"), 520, 760);
            var box = body (dlg);
            var r = export_rows (box, p, win, true);
            prepress_rows (box, r, p);
            footer (dlg, _("Export"), () => {
                var o = read_export (r);
                win.app.set_bool ("export-crop-marks", o.crop_marks);
                win.export_pdf_to.begin (p, o, name ?? win.base_name (_("Publication")));
            });
            dlg.open_dialog ();
        }

        public static void export_images (PublishWindow win) {
            var dlg = make (win, _("Export Images"), 480, 560);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Images"), _("One file per page"));
            string[] fmts = { "PNG", "JPEG", "TIFF", "GIF", "BMP" };
            var fmt = new SelectionRow (_("Format"), fmts, fmts[0]);
            g.add_row (fmt);
            var dpi = new SpinRow (_("Resolution (ppi)"), null, 36, 1200, 1, win.app.get_int ("export-dpi", 150));
            g.add_row (dpi);
            var q = new SpinRow (_("JPEG Quality"), null, 10, 100, 1, 90);
            g.add_row (q);
            var range = new EntryRow (_("Pages to Export"));
            range.tooltip_text = _("Leave empty for all pages, or type ranges such as 1-3, 6");
            g.add_row (range);
            var bleed = new SwitchRow (_("Include Bleed"), null, false);
            g.add_row (bleed);
            var trans = new SwitchRow (_("Transparent Background"), _("PNG and GIF"), false);
            g.add_row (trans);
            var cmyk = new SwitchRow (_("CMYK TIFF"), _("Convert with the document's CMYK profile"), false);
            g.add_row (cmyk);
            box.append (g);
            footer (dlg, _("Export"), () => {
                var o = new ExportOptions ();
                o.dpi = dpi.value;
                o.jpeg_quality = (int) q.value;
                o.ranges = range.text;
                o.bleed = bleed.switch_btn.active;
                o.transparent = trans.switch_btn.active && (fmt.current_value == "PNG" || fmt.current_value == "GIF");
                o.image_cmyk = cmyk.switch_btn.active && fmt.current_value == "TIFF";
                win.export_images_to.begin (o, fmt.current_value.down ());
            });
            dlg.open_dialog ();
        }

        public static void step_repeat (PublishWindow win) {
            if (win.canvas.selection.size == 0) {
                win.toast (_("Select objects to repeat"));
                return;
            }
            var dlg = make (win, _("Step and Repeat"), 420, 400);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Copies"));
            var count = new SpinRow (_("Count"), null, 1, 500, 1, 3);
            g.add_row (count);
            string u = win.doc.pub.settings.units;
            var b = win.canvas.selection_bounds ();
            var dx = unit_spin (g, _("Horizontal Offset"), b.w + 6, u, -10000);
            var dy = unit_spin (g, _("Vertical Offset"), 0, u, -10000);
            box.append (g);
            footer (dlg, _("Repeat"), () => {
                double f = Units.factor (u);
                win.duplicate_items (dx.value * f, dy.value * f, (int) count.value);
            });
            dlg.open_dialog ();
        }

        public static void insert_table (PublishWindow win) {
            var dlg = make (win, _("Insert Table"), 400, 420);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Size"), _("Rows and columns can be added later"));
            var rows = new SpinRow (_("Rows"), null, 1, 200, 1, 5);
            g.add_row (rows);
            var cols = new SpinRow (_("Columns"), null, 1, 40, 1, 3);
            g.add_row (cols);
            var hdr = new SpinRow (_("Header Rows"), null, 0, 10, 1, 1);
            g.add_row (hdr);
            box.append (g);
            footer (dlg, _("Insert"), () => win.insert_table ((int) rows.value, (int) cols.value, (int) hdr.value));
            dlg.open_dialog ();
        }

        public static void insert_pages (PublishWindow win) {
            var dlg = make (win, _("Insert Pages"), 420, 440);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Pages"));
            var count = new SpinRow (_("Number of Pages"), null, 1, 500, 1, 1);
            g.add_row (count);
            string[] where = { _("After Current Page"), _("Before Current Page"), _("At End of Document") };
            var at = new SelectionRow (_("Insert"), where, where[0]);
            g.add_row (at);
            string[] masters = { _("None") };
            string cur = _("None");
            var pg = win.doc.page;
            foreach (var m in win.doc.pub.masters) {
                masters += m.display_name ();
                if (pg != null && pg.master == m.id) cur = m.display_name ();
            }
            var mr = new SelectionRow (_("Master"), masters, cur);
            g.add_row (mr);
            box.append (g);
            footer (dlg, _("Insert"), () => {
                int pos = win.doc.current_page + 1;
                if (at.current_value == where[1]) pos = win.doc.current_page;
                else if (at.current_value == where[2]) pos = win.doc.pub.pages.size;
                string m = "";
                foreach (var mm in win.doc.pub.masters) if (mm.display_name () == mr.current_value) m = mm.id;
                win.add_pages (pos, (int) count.value, m);
            });
            dlg.open_dialog ();
        }

        public static void sections (PublishWindow win, int page) {
            var p = win.doc.pub;
            var existing = p.section_starting (page);
            var dlg = make (win, _("Numbering and Section Options"), 460, 560);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Section"), _("Page %s").printf (p.page_label (page)));
            var start = new SwitchRow (_("Start Section Here"), null, existing != null || page == 0);
            start.sensitive = page > 0;
            g.add_row (start);
            var name = new EntryRow (_("Section Name"));
            name.text = existing != null ? existing.name : "";
            g.add_row (name);
            var prefix = new EntryRow (_("Prefix"));
            prefix.text = existing != null ? existing.prefix : "";
            g.add_row (prefix);
            box.append (g);
            var ng = new PreferencesGroup (_("Page Numbering"));
            string[] styles = { NumberStyle.ARABIC.label (), NumberStyle.ROMAN_LOWER.label (), NumberStyle.ROMAN_UPPER.label (), NumberStyle.ALPHA_LOWER.label (), NumberStyle.ALPHA_UPPER.label () };
            var style = new SelectionRow (_("Style"), styles, styles[existing != null ? (int) existing.style : 0]);
            ng.add_row (style);
            var cont = new SwitchRow (_("Continue from Previous Section"), null, existing != null && existing.continue_numbering);
            ng.add_row (cont);
            var num = new SpinRow (_("Start At"), null, 1, 99999, 1, existing != null ? existing.start_number : p.page_number (page));
            ng.add_row (num);
            box.append (ng);
            footer (dlg, _("Apply"), () => {
                win.edit (_("Section"), () => {
                    var s = p.section_starting (page);
                    if (!start.switch_btn.active && page > 0) {
                        if (s != null) p.sections.remove (s);
                        return;
                    }
                    if (s == null) {
                        s = new Section (page);
                        p.sections.add (s);
                    }
                    s.name = name.text;
                    s.prefix = prefix.text;
                    for (int i = 0; i < styles.length; i++) if (styles[i] == style.current_value) s.style = (NumberStyle) i;
                    s.continue_numbering = cont.switch_btn.active;
                    s.start_number = (int) num.value;
                });
                win.pages_panel.load ();
                win.content_edited ();
            });
            dlg.open_dialog ();
        }

        public static void create_guides (PublishWindow win) {
            var dlg = make (win, _("Create Guides"), 420, 520);
            var box = body (dlg);
            string u = win.doc.pub.settings.units;
            var g = new PreferencesGroup (_("Rows"));
            var rows = new SpinRow (_("Number"), null, 0, 50, 1, 0);
            g.add_row (rows);
            var rg = unit_spin (g, _("Gutter"), 12, u);
            box.append (g);
            var cg = new PreferencesGroup (_("Columns"));
            var cols = new SpinRow (_("Number"), null, 0, 50, 1, 3);
            cg.add_row (cols);
            var cgut = unit_spin (cg, _("Gutter"), 12, u);
            box.append (cg);
            var og = new PreferencesGroup (_("Options"));
            string[] fits = { _("Margins"), _("Page") };
            var fit = new SelectionRow (_("Fit Guides To"), fits, fits[0]);
            og.add_row (fit);
            var clear = new SwitchRow (_("Remove Existing Guides"), null, false);
            og.add_row (clear);
            box.append (og);
            footer (dlg, _("Create"), () => {
                var sl = win.canvas.active_slot ();
                if (sl == null) return;
                double f = Units.factor (u);
                int pi = sl.page >= 0 ? sl.page : 0;
                var area = fit.current_value == fits[0] ? win.doc.pub.margin_rect (pi) : win.doc.pub.page_rect ();
                var list = win.canvas.own_guides (sl);
                win.edit (_("Create Guides"), () => {
                    if (clear.switch_btn.active) list.clear ();
                    int nr = (int) rows.value, nc = (int) cols.value;
                    double gr = rg.value * f, gc = cgut.value * f;
                    if (nc > 1) {
                        double cw = (area.w - gc * (nc - 1)) / nc;
                        for (int i = 1; i < nc; i++) {
                            double x = area.x + i * cw + (i - 1) * gc;
                            list.add (new Guide (true, x));
                            if (gc > 0) list.add (new Guide (true, x + gc));
                        }
                    }
                    if (nr > 1) {
                        double rh = (area.h - gr * (nr - 1)) / nr;
                        for (int i = 1; i < nr; i++) {
                            double y = area.y + i * rh + (i - 1) * gr;
                            list.add (new Guide (false, y));
                            if (gr > 0) list.add (new Guide (false, y + gr));
                        }
                    }
                });
            });
            dlg.open_dialog ();
        }

        public static void go_to_page (PublishWindow win) {
            var dlg = make (win, _("Go to Page"), 360, 260);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Page"), _("Type a page label such as 3, iv or A-2"));
            var e = new EntryRow (_("Page"));
            g.add_row (e);
            box.append (g);
            footer (dlg, _("Go"), () => {
                string t = e.text.strip ();
                var p = win.doc.pub;
                for (int i = 0; i < p.pages.size; i++) {
                    if (p.page_label (i) == t) {
                        win.go_to_page (i);
                        return;
                    }
                }
                int n = int.parse (t);
                if (n >= 1 && n <= p.pages.size) win.go_to_page (n - 1);
                else win.toast (_("There is no page \"%s\"").printf (t));
            });
            e.entry_activated.connect (() => {
                string t = e.text.strip ();
                int n = int.parse (t);
                if (n >= 1 && n <= win.doc.pub.pages.size) win.go_to_page (n - 1);
                dlg.close ();
            });
            dlg.open_dialog ();
        }

        public static void rename_master (PublishWindow win, MasterPage m) {
            var dlg = make (win, _("Rename Master"), 380, 280);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Master Page"), _("The prefix %s stays the same").printf (m.id));
            var e = new EntryRow (_("Name"));
            e.text = m.name;
            g.add_row (e);
            box.append (g);
            footer (dlg, _("Rename"), () => {
                string t = e.text.strip ();
                if (t == "") return;
                win.edit (_("Rename Master"), () => m.name = t);
                win.pages_panel.load ();
            });
            dlg.open_dialog ();
        }

        public static void edit_swatch (PublishWindow win, Swatch? existing, owned NameFunc? done) {
            var p = win.doc.pub;
            var dlg = make (win, existing != null ? _("Edit Swatch") : _("New Swatch"), 440, 640);
            var box = body (dlg);
            var sw = existing != null ? existing.clone () : new Swatch.cmyk (p.unique_swatch_name (_("New Colour")), 0, 0.5, 1, 0);
            if (existing == null && !p.settings.cmyk) sw = new Swatch.rgb (p.unique_swatch_name (_("New Colour")), 0.2, 0.5, 0.9);
            var g = new PreferencesGroup (_("Swatch"));
            var name = new EntryRow (_("Name"));
            name.text = sw.name;
            g.add_row (name);
            string[] models = { "CMYK", "RGB" };
            var model = new SelectionRow (_("Colour Model"), models, sw.model == ColorModel.CMYK ? models[0] : models[1]);
            g.add_row (model);
            var spot = new SwitchRow (_("Spot Colour"), _("Printed with its own ink, such as a Pantone colour"), sw.spot);
            g.add_row (spot);
            var sgroup = new EntryRow (_("Group"));
            sgroup.text = sw.group;
            g.add_row (sgroup);
            box.append (g);
            var preview = new DrawingArea ();
            preview.set_size_request (-1, 48);
            preview.set_draw_func ((d, cr, w, h) => {
                var c = sw.rgba ();
                Renderer.round_rect (cr, 0, 0, w, h, 10);
                cr.set_source_rgba (c.r, c.g, c.b, 1);
                cr.fill ();
            });
            var vg = new PreferencesGroup (_("Values"));
            var sc = new SpinRow (_("Cyan %"), null, 0, 100, 1, Math.round (sw.c * 100));
            var sm = new SpinRow (_("Magenta %"), null, 0, 100, 1, Math.round (sw.m * 100));
            var sy = new SpinRow (_("Yellow %"), null, 0, 100, 1, Math.round (sw.y * 100));
            var sk = new SpinRow (_("Black %"), null, 0, 100, 1, Math.round (sw.k * 100));
            var sr = new SpinRow (_("Red"), null, 0, 255, 1, Math.round (sw.r * 255));
            var sgr = new SpinRow (_("Green"), null, 0, 255, 1, Math.round (sw.g * 255));
            var sb = new SpinRow (_("Blue"), null, 0, 255, 1, Math.round (sw.b * 255));
            var hex = new EntryRow (_("Hex"));
            hex.text = sw.rgba ().to_hex ();
            foreach (var r in new SpinRow[] { sc, sm, sy, sk, sr, sgr, sb }) vg.add_row (r);
            vg.add_row (hex);
            box.append (vg);
            box.append (preview);
            bool upd = false;
            Apply sync_vis = () => {
                bool cmyk = model.current_value == "CMYK";
                sc.visible = sm.visible = sy.visible = sk.visible = cmyk;
                sr.visible = sgr.visible = sb.visible = hex.visible = !cmyk;
            };
            sync_vis ();
            Apply from_cmyk = () => {
                if (upd) return;
                sw.model = ColorModel.CMYK;
                sw.c = sc.value / 100;
                sw.m = sm.value / 100;
                sw.y = sy.value / 100;
                sw.k = sk.value / 100;
                var c = ColorMath.cmyk_to_rgb (sw.c, sw.m, sw.y, sw.k);
                sw.r = c.r;
                sw.g = c.g;
                sw.b = c.b;
                preview.queue_draw ();
            };
            Apply from_rgb = () => {
                if (upd) return;
                sw.model = ColorModel.RGB;
                sw.r = sr.value / 255;
                sw.g = sgr.value / 255;
                sw.b = sb.value / 255;
                ColorMath.rgb_to_cmyk (sw.r, sw.g, sw.b, out sw.c, out sw.m, out sw.y, out sw.k);
                upd = true;
                hex.text = sw.rgba ().to_hex ();
                upd = false;
                preview.queue_draw ();
            };
            foreach (var r in new SpinRow[] { sc, sm, sy, sk }) r.spin_btn.value_changed.connect (() => from_cmyk ());
            foreach (var r in new SpinRow[] { sr, sgr, sb }) r.spin_btn.value_changed.connect (() => from_rgb ());
            hex.entry_changed.connect (() => {
                if (upd) return;
                Rgba c;
                if (!Rgba.parse_hex (hex.text, out c)) return;
                upd = true;
                sr.value = Math.round (c.r * 255);
                sgr.value = Math.round (c.g * 255);
                sb.value = Math.round (c.b * 255);
                upd = false;
                from_rgb ();
            });
            model.selected.connect ((item) => {
                sync_vis ();
                upd = true;
                if (item == "CMYK") {
                    ColorMath.rgb_to_cmyk (sw.r, sw.g, sw.b, out sw.c, out sw.m, out sw.y, out sw.k);
                    sc.value = Math.round (sw.c * 100);
                    sm.value = Math.round (sw.m * 100);
                    sy.value = Math.round (sw.y * 100);
                    sk.value = Math.round (sw.k * 100);
                    upd = false;
                    from_cmyk ();
                } else {
                    var c = sw.rgba ();
                    sr.value = Math.round (c.r * 255);
                    sgr.value = Math.round (c.g * 255);
                    sb.value = Math.round (c.b * 255);
                    upd = false;
                    from_rgb ();
                }
            });
            footer (dlg, existing != null ? _("Save") : _("Add"), () => {
                string nm = name.text.strip ();
                if (nm == "") nm = _("Colour");
                sw.spot = spot.switch_btn.active;
                sw.group = sgroup.text.strip ();
                if (existing == null) {
                    nm = p.unique_swatch_name (nm);
                    sw.name = nm;
                    win.edit (_("New Swatch"), () => p.swatches.add (sw));
                } else {
                    string old = existing.name;
                    if (nm != old && p.swatch (nm) != null) nm = p.unique_swatch_name (nm);
                    win.edit (_("Edit Swatch"), () => {
                        existing.model = sw.model;
                        existing.spot = sw.spot;
                        existing.r = sw.r;
                        existing.g = sw.g;
                        existing.b = sw.b;
                        existing.c = sw.c;
                        existing.m = sw.m;
                        existing.y = sw.y;
                        existing.k = sw.k;
                        existing.group = sw.group;
                        if (nm != old) p.rename_swatch (old, nm);
                    });
                }
                win.swatches_panel.rebuild ();
                if (done != null) done (nm);
            });
            dlg.open_dialog ();
        }

        public static void edit_paragraph_style (PublishWindow win, ParagraphStyle? existing) {
            var p = win.doc.pub;
            var dlg = make (win, existing != null ? _("Paragraph Style") : _("New Paragraph Style"), 480, 760);
            var box = body (dlg);
            var st = existing != null ? existing.clone () : new ParagraphStyle (p.styles.unique_paragraph_name (_("Paragraph Style")), StyleSheet.BASIC);
            if (existing == null) {
                var cur = win.current_paragraph ();
                if (cur != null) {
                    st.based_on = cur.style;
                    st.para = cur.fmt.clone ();
                }
            }
            var g = new PreferencesGroup (_("General"));
            var name = new EntryRow (_("Name"));
            name.text = st.name;
            g.add_row (name);
            string[] names = { _("None") };
            foreach (var o in p.styles.paragraph) if (existing == null || o != existing) names += o.name;
            var based = new SelectionRow (_("Based On"), names, st.based_on != "" ? st.based_on : names[0]);
            g.add_row (based);
            string[] nexts = { _("Same Style") };
            foreach (var o in p.styles.paragraph) nexts += o.name;
            var next = new SelectionRow (_("Next Style"), nexts, st.next != "" ? st.next : nexts[0]);
            g.add_row (next);
            var group_row = new EntryRow (_("Group"));
            group_row.text = st.group;
            g.add_row (group_row);
            string[] tags = { _("Automatic"), "P", "H1", "H2", "H3", "H4", "H5", "H6", "BlockQuote", "Caption", "Note", "Code" };
            var tag_row = new SelectionRow (_("Export Tag"), tags, st.tag != "" ? st.tag : tags[0]);
            tag_row.subtitle = _("Role in tagged PDF and EPUB");
            g.add_row (tag_row);
            box.append (g);
            var eff_p = ParaFormat.defaults ();
            var eff_c = CharFormat.defaults ();
            if (st.based_on != "") p.styles.resolve_paragraph (st.based_on, eff_p, eff_c);
            eff_p.apply (st.para);
            eff_c.apply (st.chars);
            var cg = new PreferencesGroup (_("Character"), _("Values equal to the parent style are inherited"));
            var font = new EntryRow (_("Font"));
            font.text = eff_c.font ?? "Inter";
            cg.add_row (font);
            var size = new SpinRow (_("Size (pt)"), null, 1, 1296, 0.5, eff_c.size);
            size.spin_btn.digits = 1;
            cg.add_row (size);
            var bold = new SwitchRow (_("Bold"), null, eff_c.bold == 1);
            cg.add_row (bold);
            var ital = new SwitchRow (_("Italic"), null, eff_c.italic == 1);
            cg.add_row (ital);
            var colr = new ActionRow (_("Colour"));
            var colb = new SwatchButton (win, eff_c.color ?? ColorRef.BLACK, false);
            string col_spec = eff_c.color ?? ColorRef.BLACK;
            colb.chosen.connect ((s) => col_spec = s);
            colr.add_suffix (colb);
            cg.add_row (colr);
            var track = new SpinRow (_("Tracking"), null, -500, 2000, 5, eff_c.tracking.is_nan () ? 0 : eff_c.tracking);
            cg.add_row (track);
            box.append (cg);
            var pg = new PreferencesGroup (_("Paragraph"));
            string[] aligns = { _("Left"), _("Center"), _("Right"), _("Justify"), _("Justify All Lines") };
            var align = new SelectionRow (_("Alignment"), aligns, aligns[eff_p.align.clamp (0, 4)]);
            pg.add_row (align);
            var lead = new SpinRow (_("Leading (pt, 0 is auto)"), null, 0, 1000, 0.5, eff_p.leading);
            lead.spin_btn.digits = 1;
            pg.add_row (lead);
            var li = new SpinRow (_("Left Indent (pt)"), null, -500, 1000, 1, eff_p.left_indent);
            pg.add_row (li);
            var fi = new SpinRow (_("First Line Indent (pt)"), null, -500, 1000, 1, eff_p.first_indent);
            pg.add_row (fi);
            var sbf = new SpinRow (_("Space Before (pt)"), null, 0, 1000, 1, eff_p.space_before);
            pg.add_row (sbf);
            var saf = new SpinRow (_("Space After (pt)"), null, 0, 1000, 1, eff_p.space_after);
            pg.add_row (saf);
            var drop = new SpinRow (_("Drop Cap Lines"), null, 0, 12, 1, eff_p.drop_lines);
            pg.add_row (drop);
            var hyp = new SwitchRow (_("Hyphenate"), null, eff_p.hyphenate == 1);
            pg.add_row (hyp);
            var grid = new SwitchRow (_("Align to Baseline Grid"), null, eff_p.align_grid == 1);
            pg.add_row (grid);
            var keep = new SwitchRow (_("Keep with Next"), null, eff_p.keep_next == 1);
            pg.add_row (keep);
            string[] lists = { _("None"), _("Bullets"), _("Numbers") };
            var list = new SelectionRow (_("List"), lists, lists[eff_p.list_type.clamp (0, 2)]);
            pg.add_row (list);
            var rule = new SwitchRow (_("Rule Below"), null, eff_p.rule_below != null && eff_p.rule_below != "");
            pg.add_row (rule);
            box.append (pg);
            footer (dlg, existing != null ? _("Save") : _("Create"), () => {
                string nm = name.text.strip ();
                if (nm == "") return;
                string b = based.current_value == names[0] ? "" : based.current_value;
                if (existing != null && b != "" && p.styles.would_cycle (existing.name, b)) b = existing.based_on;
                var parent_p = ParaFormat.defaults ();
                var parent_c = CharFormat.defaults ();
                if (b != "") p.styles.resolve_paragraph (b, parent_p, parent_c);
                var np = new ParaFormat ();
                var nc = new CharFormat ();
                if (font.text.strip () != parent_c.font) nc.font = font.text.strip ();
                if (Math.fabs (size.value - parent_c.size) > 0.01) nc.size = size.value;
                if ((bold.switch_btn.active ? 1 : 0) != parent_c.bold) nc.bold = bold.switch_btn.active ? 1 : 0;
                if ((ital.switch_btn.active ? 1 : 0) != parent_c.italic) nc.italic = ital.switch_btn.active ? 1 : 0;
                if (col_spec != parent_c.color) nc.color = col_spec;
                if (Math.fabs (track.value - (parent_c.tracking.is_nan () ? 0 : parent_c.tracking)) > 0.01) nc.tracking = track.value;
                int al = 0;
                for (int i = 0; i < aligns.length; i++) if (aligns[i] == align.current_value) al = i;
                if (al != parent_p.align) np.align = al;
                if (Math.fabs (lead.value - parent_p.leading) > 0.01) np.leading = lead.value;
                if (Math.fabs (li.value - parent_p.left_indent) > 0.01) np.left_indent = li.value;
                if (Math.fabs (fi.value - parent_p.first_indent) > 0.01) np.first_indent = fi.value;
                if (Math.fabs (sbf.value - parent_p.space_before) > 0.01) np.space_before = sbf.value;
                if (Math.fabs (saf.value - parent_p.space_after) > 0.01) np.space_after = saf.value;
                if ((int) drop.value != parent_p.drop_lines) {
                    np.drop_lines = (int) drop.value;
                    np.drop_chars = 1;
                }
                if ((hyp.switch_btn.active ? 1 : 0) != parent_p.hyphenate) np.hyphenate = hyp.switch_btn.active ? 1 : 0;
                if ((grid.switch_btn.active ? 1 : 0) != parent_p.align_grid) np.align_grid = grid.switch_btn.active ? 1 : 0;
                if ((keep.switch_btn.active ? 1 : 0) != parent_p.keep_next) np.keep_next = keep.switch_btn.active ? 1 : 0;
                int lt = 0;
                for (int i = 0; i < lists.length; i++) if (lists[i] == list.current_value) lt = i;
                if (lt != parent_p.list_type) {
                    np.list_type = lt;
                    if (lt > 0 && li.value < 1) {
                        np.left_indent = 18;
                        np.first_indent = -14;
                    }
                }
                np.rule_below = rule.switch_btn.active ? "0.75;" + ColorRef.BLACK + ";4" : (parent_p.rule_below != "" ? "" : null);
                np.tabs = st.para.tabs;
                np.bullet = st.para.bullet;
                np.number_format = st.para.number_format;
                np.copy_composition (st.para);
                string grp = group_row.text.strip ();
                string tg = tag_row.current_value == tags[0] ? "" : tag_row.current_value;
                string nx = next.current_value == nexts[0] ? "" : next.current_value;
                win.edit (existing != null ? _("Edit Style") : _("New Style"), () => {
                    if (existing == null) {
                        var ns = new ParagraphStyle (p.styles.unique_paragraph_name (nm), b);
                        ns.para = np;
                        ns.chars = nc;
                        ns.next = nx;
                        ns.group = grp;
                        ns.tag = tg;
                        p.styles.paragraph.add (ns);
                    } else {
                        string old = existing.name;
                        if (nm != old && p.styles.find_paragraph (nm) == null) {
                            existing.name = nm;
                            foreach (var o in p.styles.paragraph) {
                                if (o.based_on == old) o.based_on = nm;
                                if (o.next == old) o.next = nm;
                            }
                            foreach (var s in p.stories.values) foreach (var q in s.paras) if (q.style == old) q.style = nm;
                        }
                        existing.based_on = b;
                        existing.para = np;
                        existing.chars = nc;
                        existing.next = nx;
                        existing.group = grp;
                        existing.tag = tg;
                    }
                });
                win.styles_panel.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void edit_character_style (PublishWindow win, CharacterStyle? existing) {
            var p = win.doc.pub;
            var dlg = make (win, existing != null ? _("Character Style") : _("New Character Style"), 440, 600);
            var box = body (dlg);
            var st = existing != null ? existing.clone () : new CharacterStyle (p.styles.unique_character_name (_("Character Style")));
            var g = new PreferencesGroup (_("General"));
            var name = new EntryRow (_("Name"));
            name.text = st.name;
            g.add_row (name);
            string[] names = { _("None") };
            foreach (var o in p.styles.character) if (existing == null || o != existing) names += o.name;
            var based = new SelectionRow (_("Based On"), names, st.based_on != "" ? st.based_on : names[0]);
            g.add_row (based);
            var cgroup = new EntryRow (_("Group"));
            cgroup.text = st.group;
            g.add_row (cgroup);
            box.append (g);
            var cg = new PreferencesGroup (_("Character"), _("Only the options switched on are applied"));
            var use_font = new SwitchRow (_("Set Font"), null, st.chars.font != null);
            cg.add_row (use_font);
            var font = new EntryRow (_("Font"));
            font.text = st.chars.font ?? "Inter";
            cg.add_row (font);
            var use_size = new SwitchRow (_("Set Size"), null, !st.chars.size.is_nan ());
            cg.add_row (use_size);
            var size = new SpinRow (_("Size (pt)"), null, 1, 1296, 0.5, st.chars.size.is_nan () ? 11 : st.chars.size);
            cg.add_row (size);
            var bold = new SwitchRow (_("Bold"), null, st.chars.bold == 1);
            cg.add_row (bold);
            var ital = new SwitchRow (_("Italic"), null, st.chars.italic == 1);
            cg.add_row (ital);
            var und = new SwitchRow (_("Underline"), null, st.chars.underline == 1);
            cg.add_row (und);
            var caps = new SwitchRow (_("Small Caps"), null, st.chars.caps == 2);
            cg.add_row (caps);
            var use_col = new SwitchRow (_("Set Colour"), null, st.chars.color != null);
            cg.add_row (use_col);
            var colr = new ActionRow (_("Colour"));
            string col_spec = st.chars.color ?? ColorRef.swatch ("Magenta");
            var colb = new SwatchButton (win, col_spec, false);
            colb.chosen.connect ((s) => {
                col_spec = s;
                use_col.switch_btn.active = true;
            });
            colr.add_suffix (colb);
            cg.add_row (colr);
            box.append (cg);
            footer (dlg, existing != null ? _("Save") : _("Create"), () => {
                string nm = name.text.strip ();
                if (nm == "") return;
                var nc = st.chars.clone ();
                nc.font = use_font.switch_btn.active ? font.text.strip () : null;
                nc.size = use_size.switch_btn.active ? size.value : double.NAN;
                nc.color = null;
                string cgrp = cgroup.text.strip ();
                nc.bold = bold.switch_btn.active ? 1 : -1;
                nc.italic = ital.switch_btn.active ? 1 : -1;
                nc.underline = und.switch_btn.active ? 1 : -1;
                nc.caps = caps.switch_btn.active ? 2 : -1;
                if (use_col.switch_btn.active) nc.color = col_spec;
                string b = based.current_value == names[0] ? "" : based.current_value;
                win.edit (existing != null ? _("Edit Style") : _("New Style"), () => {
                    if (existing == null) {
                        var ns = new CharacterStyle (p.styles.unique_character_name (nm), b);
                        ns.chars = nc;
                        ns.group = cgrp;
                        p.styles.character.add (ns);
                    } else {
                        string old = existing.name;
                        if (nm != old && p.styles.find_character (nm) == null) {
                            existing.name = nm;
                            foreach (var s in p.stories.values) foreach (var q in s.paras) foreach (var r in q.runs) if (r.cstyle == old) r.cstyle = nm;
                        }
                        existing.based_on = b;
                        existing.chars = nc;
                        existing.group = cgrp;
                    }
                });
                win.styles_panel.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void add_tab (PublishWindow win) {
            var dlg = make (win, _("Add Tab Stop"), 400, 420);
            var box = body (dlg);
            string u = win.doc.pub.settings.units;
            var g = new PreferencesGroup (_("Tab Stop"));
            var pos = unit_spin (g, _("Position"), 72, u);
            string[] kinds = { _("Left"), _("Center"), _("Right"), _("Decimal") };
            var kind = new SelectionRow (_("Alignment"), kinds, kinds[0]);
            g.add_row (kind);
            var leader = new EntryRow (_("Leader"));
            leader.tooltip_text = _("Characters that fill the space before the tab, such as a dot");
            g.add_row (leader);
            box.append (g);
            footer (dlg, _("Add"), () => {
                var l = TabStop.parse (win.current_para_format ().tabs);
                int k = 0;
                for (int i = 0; i < kinds.length; i++) if (kinds[i] == kind.current_value) k = i;
                l.add (new TabStop (pos.value * Units.factor (u), (TabKind) k, leader.text));
                l.sort ((a, b) => a.pos < b.pos ? -1 : (a.pos > b.pos ? 1 : 0));
                string s = TabStop.serialize (l);
                win.format_paras (_("Tabs"), (p) => p.fmt.tabs = s);
            });
            dlg.open_dialog ();
        }

        private class SpellHit {
            public Story story;
            public TextPos a;
            public TextPos b;
            public string word;
        }

        public static void spelling (PublishWindow win) {
            var sp = Singularity.Text.SpellChecker.get_default ();
            if (!sp.available) {
                win.show_error (_("Spell Checking Unavailable"), _("No spelling dictionary is installed."));
                return;
            }
            var hits = new Gee.ArrayList<SpellHit> ();
            var ignored = new Gee.HashSet<string> ();
            var stories = new Gee.ArrayList<Story> ();
            var ids = new Gee.ArrayList<int> ();
            ids.add_all (win.doc.pub.stories.keys);
            ids.sort ((a, b) => a - b);
            foreach (int id in ids) stories.add (win.doc.pub.stories[id]);
            win.doc.pub.walk ((r) => {
                var tb = r.item as TableItem;
                if (tb != null) foreach (var row in tb.cells) foreach (var c in row) stories.add (c.story);
                return true;
            });
            foreach (var s in stories) {
                for (int pi = 0; pi < s.paras.size; pi++) {
                    string t = s.paras[pi].text ();
                    int n = t.char_count ();
                    int i = 0;
                    while (i < n) {
                        unichar c = t.get_char (t.index_of_nth_char (i));
                        if (!c.isalpha ()) {
                            i++;
                            continue;
                        }
                        int j = i;
                        while (j < n && Story.is_word_char (t.get_char (t.index_of_nth_char (j)))) j++;
                        string w = t.substring (t.index_of_nth_char (i), t.index_of_nth_char (j) - t.index_of_nth_char (i));
                        while (w.has_suffix ("'") || w.has_suffix ("’")) w = w.substring (0, w.length - (w.has_suffix ("'") ? 1 : 3));
                        if (w.char_count () > 1 && !sp.check (w)) {
                            var h = new SpellHit ();
                            h.story = s;
                            h.a = TextPos (pi, i);
                            h.b = TextPos (pi, i + w.char_count ());
                            h.word = w;
                            hits.add (h);
                        }
                        i = j;
                    }
                }
            }
            if (hits.size == 0) {
                var t = new Toast (_("No spelling mistakes found"));
                win.add_toast (t);
                return;
            }
            var dlg = make (win, _("Check Spelling"), 420, 520);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Not in Dictionary"));
            var word_row = new ActionRow ("");
            g.add_row (word_row);
            var change = new EntryRow (_("Change To"));
            g.add_row (change);
            box.append (g);
            var sug_group = new PreferencesGroup (_("Suggestions"));
            box.append (sug_group);
            int idx = 0;
            Apply show = null;
            show = () => {
                while (idx < hits.size && ignored.contains (hits[idx].word)) idx++;
                if (idx >= hits.size) {
                    win.toast (_("Spell check complete"));
                    dlg.close ();
                    return;
                }
                var h = hits[idx];
                word_row.title = h.word;
                word_row.subtitle = _("%d of %d").printf (idx + 1, hits.size);
                sug_group.clear ();
                string[] sugs = sp.suggest (h.word, 6);
                change.text = sugs.length > 0 ? sugs[0] : h.word;
                foreach (string s in sugs) {
                    string ss = s;
                    var r = new ActionRow (s);
                    var b = new Button.with_label (_("Use"));
                    b.valign = Align.CENTER;
                    b.clicked.connect (() => change.text = ss);
                    r.add_suffix (b);
                    sug_group.add_row (r);
                }
                if (sugs.length == 0) sug_group.add_row (new ActionRow (_("No suggestions")));
            };
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var close = new Button.with_label (_("Close"));
            dlg.set_cancel_button (close);
            close.clicked.connect (() => dlg.close ());
            var ignore = new Button.with_label (_("Ignore All"));
            ignore.clicked.connect (() => {
                ignored.add (hits[idx].word);
                idx++;
                show ();
            });
            var add = new Button.with_label (_("Add"));
            add.tooltip_text = _("Add to Dictionary");
            add.clicked.connect (() => {
                sp.add_to_dictionary (hits[idx].word);
                ignored.add (hits[idx].word);
                idx++;
                show ();
            });
            var chg = new Button.with_label (_("Change"));
            chg.add_css_class ("suggested-action");
            chg.clicked.connect (() => {
                var h = hits[idx];
                string rep = change.text;
                win.edit (_("Spelling"), () => {
                    var tmpl = h.story.format_at (TextPos (h.a.para, h.a.offset + 1)).clone ();
                    h.story.delete_range (h.a, h.b);
                    h.story.insert_text (h.a, rep, tmpl);
                });
                int delta = rep.char_count () - h.word.char_count ();
                for (int k = idx + 1; k < hits.size; k++) {
                    if (hits[k].story == h.story && hits[k].a.para == h.a.para) {
                        hits[k].a = TextPos (hits[k].a.para, hits[k].a.offset + delta);
                        hits[k].b = TextPos (hits[k].b.para, hits[k].b.offset + delta);
                    }
                }
                idx++;
                show ();
            });
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            bar.append (close);
            bar.append (ignore);
            bar.append (add);
            bar.append (chg);
            dlg.content_box.append (bar);
            show ();
            dlg.open_dialog ();
        }
    }
}
