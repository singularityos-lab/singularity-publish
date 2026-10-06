namespace Singularity.Apps.Publish {

    public class PublishPrintSource : Singularity.Print.PageSource {
        public Publication pub { get; private set; }
        public Gee.ArrayList<Sheet> sheets = new Gee.ArrayList<Sheet> ();
        private Exporter exporter;
        private Gee.ArrayList<Exporter> plate_exporters = new Gee.ArrayList<Exporter> ();
        private Gee.ArrayList<string> plates = new Gee.ArrayList<string> ();

        public override bool imposes_pages {
            get { return true; }
        }

        public PublishPrintSource (Publication pub, string title, int current, ExportOptions? initial = null) {
            this.pub = pub;
            this.title = title;
            current_page = current.clamp (0, int.max (pub.pages.size - 1, 0));
            document_pages = pub.pages.size;
            extra_options = prepress_options (pub, initial);
        }

        public static Singularity.Print.ExtraOptions prepress_options (Publication pub, ExportOptions? initial) {
            var x = new Singularity.Print.ExtraOptions (_("Prepress"), _("Marks, bleed and imposition for the printed sheets"));
            string hint = pub.settings.impose;
            bool nup = hint.has_prefix ("nup");
            int across = 2, down = 2;
            string[] hp = hint.split (":");
            if (hp.length >= 2) {
                string[] cr = hp[1].split ("x");
                if (cr.length == 2) {
                    across = int.parse (cr[0]).clamp (1, 20);
                    down = int.parse (cr[1]).clamp (1, 20);
                }
            }
            string layout = nup ? "nup" : (hint.has_prefix ("booklet") ? "booklet" : "none");
            bool has_bleed = pub.settings.max_bleed () > 0;
            x.add_switch ("bleed", _("Include Bleed"), _("Bleed of %s from the document setup").printf (Units.format (pub.settings.max_bleed (), pub.settings.units)), initial != null ? initial.bleed && has_bleed : false);
            x.add_switch ("crop-marks", _("Crop Marks"), null, initial != null ? initial.crop_marks : nup);
            x.add_switch ("bleed-marks", _("Bleed Marks"), null, initial != null && initial.bleed_marks);
            x.add_switch ("registration-marks", _("Registration Marks"), null, initial != null && initial.reg_marks);
            x.add_switch ("colour-bars", _("Colour Bars"), null, initial != null && initial.color_bars);
            x.add_switch ("page-info", _("Page Information"), _("Title, page and date beside each page"), initial != null && initial.page_info);
            if (pub.settings.facing) x.add_switch ("spreads", _("Spreads"), _("Facing pages side by side"), initial != null && initial.spreads);
            x.add_choice ("imposition", _("Imposition"), { "none", "nup", "booklet", "signatures", "tile" }, { _("None"), _("Several per Sheet"), _("Booklet (Saddle Stitch)"), _("Signatures (Perfect Binding)"), _("Tiled Poster") }, layout);
            x.add_choice ("signature", _("Pages per Signature"), { "4", "8", "16" }, { "4", "8", "16" }, "16");
            x.add_number ("creep", _("Creep"), _("Points the inner pages move toward the spine, per signature"), 0, 10, 0.1, 0);
            x.show_when ("signature", "imposition", { "signatures" });
            x.show_when ("creep", "imposition", { "signatures" });
            x.add_number ("tile-scale", _("Poster Size %"), _("Size of the printed poster compared with the page"), 10, 1000, 10, 100);
            x.add_number ("tile-overlap", _("Tile Overlap"), _("Points repeated on neighbouring sheets for gluing"), 0, 72, 1, 18);
            x.add_switch ("separations", _("Separations"), _("One sheet per ink: %s").printf (string.joinv (", ", PrepressExport.plates (pub).to_array ())), false);
            x.add_number ("across", _("Across"), null, 1, 20, 1, across);
            x.add_number ("down", _("Down"), null, 1, 20, 1, down);
            x.add_number ("gap", _("Gap"), _("Points between pages"), 0, 200, 1, 0);
            x.add_switch ("step-repeat", _("Step and Repeat"), _("Fill each sheet with copies of the same page, as for business cards"), nup);
            if (pub.settings.facing) x.show_when ("spreads", "imposition", { "none" });
            x.show_when ("across", "imposition", { "nup" });
            x.show_when ("down", "imposition", { "nup" });
            x.show_when ("gap", "imposition", { "nup" });
            x.show_when ("step-repeat", "imposition", { "nup" });
            x.show_when ("tile-scale", "imposition", { "tile" });
            x.show_when ("tile-overlap", "imposition", { "tile" });
            x.show_when ("bleed-marks", "imposition", { "none" });
            x.show_when ("colour-bars", "imposition", { "none" });
            x.show_when ("page-info", "imposition", { "none" });
            x.add_note ("colour", _("Colour"), _("Composite pages go to the printer in RGB converted through %s. Turn on Separations for one sheet per ink with overprint and spot colours, or export PDF/X for a commercial printer.").printf (ColorManager.for_settings (pub.settings).description ()));
            return x;
        }

        public static ExportOptions options_for (Singularity.Print.ExtraOptions x, double sheet_w, double sheet_h, int[] selection) {
            var o = new ExportOptions ();
            o.bleed = x.get_bool ("bleed");
            o.crop_marks = x.get_bool ("crop-marks");
            string layout = x.get_choice ("imposition");
            o.impose = layout == "nup" ? ImposeMode.NUP : (layout == "booklet" ? ImposeMode.BOOKLET : (layout == "tile" ? ImposeMode.TILE : (layout == "signatures" ? ImposeMode.SIGNATURES : ImposeMode.NONE)));
            if (o.impose == ImposeMode.SIGNATURES) {
                o.signature = int.parse (x.get_choice ("signature"));
                o.creep = x.get_number ("creep");
            }
            o.tile_scale = x.get_number ("tile-scale") / 100;
            o.tile_overlap = x.get_number ("tile-overlap");
            o.separations = x.get_bool ("separations");
            bool single = o.impose == ImposeMode.NONE;
            o.bleed_marks = single && x.get_bool ("bleed-marks");
            o.reg_marks = x.get_bool ("registration-marks");
            o.color_bars = single && x.get_bool ("colour-bars");
            o.page_info = single && x.get_bool ("page-info");
            o.spreads = single && x.get_bool ("spreads");
            o.cols = (int) x.get_number ("across");
            o.rows = (int) x.get_number ("down");
            o.gap = x.get_number ("gap");
            o.step_repeat = x.get_bool ("step-repeat");
            if (o.impose == ImposeMode.BOOKLET) {
                o.sheet_w = double.max (sheet_w, sheet_h);
                o.sheet_h = double.min (sheet_w, sheet_h);
            } else {
                o.sheet_w = sheet_w;
                o.sheet_h = sheet_h;
            }
            o.ranges = selection.length > 0 ? Singularity.Print.PageRanges.format (selection) : "";
            return o;
        }

        public override async int paginate (Singularity.Print.PageFormat format) throws Error {
            var o = options_for (extra_options, format.width, format.height, page_selection);
            exporter = new Exporter (pub, o);
            sheets = exporter.sheets ();
            plates.clear ();
            plate_exporters.clear ();
            if (o.separations) {
                plates.add_all (PrepressExport.selected_plates (pub, o));
                foreach (string ink in plates) plate_exporters.add (new Exporter (PrepressExport.plate_publication (pub, ink), o));
            }
            double w = 1, h = 1;
            foreach (var sh in sheets) {
                w = double.max (w, sh.w);
                h = double.max (h, sh.h);
            }
            page_width = w;
            page_height = h;
            return plates.size > 0 ? sheets.size * plates.size : sheets.size;
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (exporter == null || index < 0) return;
            int plate = -1;
            if (plates.size > 0) {
                plate = index % plates.size;
                index = index / plates.size;
            }
            if (index >= sheets.size) return;
            var sh = sheets[index];
            cr.save ();
            cr.translate ((page_width - sh.w) / 2, (page_height - sh.h) / 2);
            cr.rectangle (0, 0, sh.w, sh.h);
            cr.clip ();
            if (plate >= 0) {
                plate_exporters[plate].draw_sheet (cr, sh);
                PrepressExport.draw_plate_label (cr, sh, "%s  %s".printf (sh.label, plates[plate]));
            } else {
                exporter.draw_sheet (cr, sh);
            }
            cr.restore ();
        }
    }
}
