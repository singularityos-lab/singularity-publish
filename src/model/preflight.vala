namespace Singularity.Apps.Publish {

    public enum Severity {
        ERROR,
        WARNING,
        INFO
    }

    public enum IssueKind {
        MISSING_LINK,
        MODIFIED_LINK,
        LOW_RES,
        OVERSET,
        MISSING_FONT,
        RGB_IMAGE,
        RGB_COLOR,
        OUTSIDE_BLEED,
        OFF_PAGE,
        EMPTY_FRAME,
        SPOT_COLOR,
        ALT_TEXT,
        CONTRAST,
        NO_TITLE,
        TABLE_HEADER,
        LINK_TEXT,
        SMALL_TEXT,
        TRANSPARENCY,
        EMPTY_PAGE,
        HIGH_RES,
        INK_LIMIT,
        BLEED_SETTING,
        PRINT_TEXT_SIZE
    }

    public class PreflightIssue {
        public Severity severity;
        public IssueKind kind;
        public string message;
        public int page = -1;
        public int item = -1;
        public string master = "";

        public PreflightIssue (Severity severity, IssueKind kind, string message, int page, int item) {
            this.severity = severity;
            this.kind = kind;
            this.message = message;
            this.page = page;
            this.item = item;
        }

        public string category () {
            switch (kind) {
                case IssueKind.MISSING_LINK:
                case IssueKind.MODIFIED_LINK:
                    return _("Links");
                case IssueKind.LOW_RES:
                case IssueKind.HIGH_RES:
                case IssueKind.RGB_IMAGE:
                    return _("Images");
                case IssueKind.OVERSET:
                case IssueKind.MISSING_FONT:
                case IssueKind.PRINT_TEXT_SIZE:
                    return _("Text");
                case IssueKind.RGB_COLOR:
                case IssueKind.SPOT_COLOR:
                case IssueKind.TRANSPARENCY:
                case IssueKind.INK_LIMIT:
                    return _("Colour");
                case IssueKind.ALT_TEXT:
                case IssueKind.CONTRAST:
                case IssueKind.NO_TITLE:
                case IssueKind.TABLE_HEADER:
                case IssueKind.LINK_TEXT:
                case IssueKind.SMALL_TEXT:
                    return _("Accessibility");
                default:
                    return _("Layout");
            }
        }
    }

    public delegate bool FontCheck (string family);

    public class Preflight {
        public Publication pub;
        public double min_ppi = 250;
        public double error_ppi = 150;
        public bool check_print = true;
        public bool check_accessibility = false;
        public bool check_general = true;
        public PreflightProfile? profile = null;
        public unowned FontCheck? font_check = null;
        public Gee.ArrayList<PreflightIssue> issues = new Gee.ArrayList<PreflightIssue> ();

        public Preflight (Publication pub) {
            this.pub = pub;
        }

        public static bool system_has_font (string family) {
            var fm = Pango.CairoFontMap.get_default ();
            Pango.FontFamily[] fams;
            fm.list_families (out fams);
            string want = family.down ();
            foreach (var f in fams) if (f.get_name ().down () == want) return true;
            return false;
        }

        public void use_profile (PreflightProfile p) {
            profile = p;
            min_ppi = p.min_ppi;
            error_ppi = p.error_ppi;
            check_accessibility = p.accessibility;
            check_print = true;
            check_general = true;
        }

        public void add (Severity s, IssueKind k, string msg, int page, int item) {
            if (profile != null && !profile.allows (k)) return;
            issues.add (new PreflightIssue (s, k, msg, page, item));
        }

        public int count (Severity s) {
            int n = 0;
            foreach (var i in issues) if (i.severity == s) n++;
            return n;
        }

        public Gee.ArrayList<PreflightIssue> run () {
            issues.clear ();
            if (check_accessibility) new AccessibilityChecker (pub, this).run ();
            if (!check_print && !check_general) return issues;
            var cache = new LayoutCache (pub);
            var store = ImageStore.get_default ();
            var bleed_ok = new Gee.HashSet<int> ();
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var pg = pub.pages[pi];
                var bleed = pub.bleed_rect (pi);
                var page_r = pub.page_rect (pi);
                foreach (var it in pg.items) {
                    check_item (it, pi, cache, store);
                    var b = it.bounds ();
                    if (!b.intersects (page_r)) {
                        add (Severity.INFO, IssueKind.OFF_PAGE, _("%s is on the pasteboard and will not print").printf (it.kind_label ()), pi, it.id);
                        continue;
                    }
                    if (!b.inside (bleed) && !bleed_ok.contains (it.id)) {
                        add (Severity.WARNING, IssueKind.OUTSIDE_BLEED, _("%s extends past the bleed and will be cut off").printf (it.kind_label ()), pi, it.id);
                    }
                }
            }
            foreach (var s in pub.stories.values) {
                var frames = pub.thread_frames (s.id);
                if (frames.size == 0) continue;
                var r = pub.find_item (frames[0].id);
                if (r != null && r.master != null) continue;
                var res = cache.story (s.id);
                if (res.overset) {
                    var last = frames[frames.size - 1];
                    int page = cache.get_engine ().page_of_frame (last);
                    add (Severity.ERROR, IssueKind.OVERSET, ngettext ("Overset text: %d character does not fit", "Overset text: %d characters do not fit", res.overset_chars).printf (res.overset_chars), page, last.id);
                }
            }
            foreach (var m in pub.masters) {
                var all = new Gee.ArrayList<Item> ();
                all.add_all (m.items);
                all.add_all (m.left_items);
                foreach (var it in all) check_item (it, -1, cache, store);
            }
            foreach (string f in pub.used_fonts ()) {
                bool ok = font_check != null ? font_check (f) : system_has_font (f);
                if (!ok) add (Severity.ERROR, IssueKind.MISSING_FONT, _("Font \"%s\" is not installed; a substitute is used").printf (f), -1, -1);
            }
            if (pub.settings.cmyk) {
                foreach (var sw in pub.swatches) {
                    if (sw.model == ColorModel.RGB && pub.swatch_in_use (sw.name)) add (Severity.WARNING, IssueKind.RGB_COLOR, _("Swatch \"%s\" is RGB in a CMYK job").printf (sw.name), -1, -1);
                }
            }
            int spots = 0;
            foreach (var sw in pub.swatches) if (sw.spot && pub.swatch_in_use (sw.name)) spots++;
            if (spots > 0 && check_print) add (Severity.INFO, IssueKind.SPOT_COLOR, ngettext ("%d spot colour is used; export a CMYK or PDF/X file or separations to keep it as its own plate", "%d spot colours are used; export a CMYK or PDF/X file or separations to keep them as their own plates", spots).printf (spots), -1, -1);
            if (check_print && uses_transparency ()) add (Severity.INFO, IssueKind.TRANSPARENCY, _("The publication uses transparency or soft effects; choose PDF/X-4 rather than PDF/X-1a for commercial print"), -1, -1);
            for (int pi = 0; pi < pub.pages.size && check_general; pi++) {
                if (pub.pages[pi].items.size == 0 && pub.master_items_for (pi).size == 0) add (Severity.INFO, IssueKind.EMPTY_PAGE, _("Page %s is empty").printf (pub.page_label (pi)), pi, -1);
            }
            if (profile != null) profile_checks (cache, store);
            return issues;
        }

        private void profile_checks (LayoutCache cache, ImageStore store) {
            var p = profile;
            var s = pub.settings;
            if (p.bleed && p.min_bleed > 0) {
                double least = double.min (double.min (s.bleed_top, s.bleed_bottom), double.min (s.bleed_inside, s.bleed_outside));
                if (least + 0.01 < p.min_bleed) add (Severity.ERROR, IssueKind.BLEED_SETTING, _("The document bleed is %s; this profile needs at least %s").printf (Units.format (least, "mm"), Units.format (p.min_bleed, "mm")), -1, -1);
            }
            if (p.color && !p.allow_spot) {
                foreach (var sw in pub.swatches) if (sw.spot && pub.swatch_in_use (sw.name)) add (Severity.ERROR, IssueKind.SPOT_COLOR, _("Spot colour \"%s\" is not allowed by this profile").printf (sw.name), -1, -1);
            }
            if (p.color && p.ink_limit > 0) {
                var cm = ColorManager.for_settings (s);
                foreach (var sw in pub.swatches) {
                    if (!pub.swatch_in_use (sw.name)) continue;
                    double tac = swatch_ink (sw, cm);
                    if (tac > p.ink_limit + 0.5) add (Severity.WARNING, IssueKind.INK_LIMIT, _("Swatch \"%s\" uses %d%% total ink, over the %d%% limit").printf (sw.name, (int) Math.round (tac), (int) p.ink_limit), -1, -1);
                }
                var seen = new Gee.HashSet<string> ();
                pub.walk ((r) => {
                    var im = r.item as ImageFrame;
                    if (im == null) return true;
                    int page = r.page != null ? pub.pages.index_of (r.page) : -1;
                    var inf = store.info (pub, im);
                    if (inf == null || inf.surface == null || inf.vector) return true;
                    string key = im.link != "" ? im.link : im.media;
                    if (!seen.add (key)) return true;
                    double tac = image_ink (inf, cm);
                    if (tac > p.ink_limit + 0.5) {
                        string name = im.link != "" ? Path.get_basename (im.link) : _("Embedded image");
                        add (Severity.WARNING, IssueKind.INK_LIMIT, _("\"%s\" reaches %d%% total ink, over the %d%% limit").printf (name, (int) Math.round (tac), (int) p.ink_limit), page, im.id);
                    }
                    return true;
                });
            }
            if (p.images && p.max_ppi > 0) {
                pub.walk ((r) => {
                    var im = r.item as ImageFrame;
                    if (im == null) return true;
                    var inf = store.info (pub, im);
                    if (inf == null || inf.vector) return true;
                    var pl = ImageStore.place (im, inf);
                    double ppi = double.min (pl.ppi_x (), pl.ppi_y ());
                    if (ppi > p.max_ppi) {
                        string name = im.link != "" ? Path.get_basename (im.link) : _("Embedded image");
                        add (Severity.INFO, IssueKind.HIGH_RES, _("\"%s\" is %d ppi, more than the %d ppi this profile needs").printf (name, (int) Math.round (ppi), (int) p.max_ppi), r.page != null ? pub.pages.index_of (r.page) : -1, im.id);
                    }
                    return true;
                });
            }
            if (p.min_text > 0) {
                foreach (var st in pub.stories.values) {
                    var frames = pub.thread_frames (st.id);
                    if (frames.size == 0) continue;
                    double smallest = double.MAX;
                    foreach (var para in st.paras) {
                        var pf = ParaFormat.defaults ();
                        var cf = CharFormat.defaults ();
                        pub.styles.resolve_paragraph (para.style, pf, cf);
                        foreach (var run in para.runs) {
                            if (run.text.strip () == "" && run.field == "") continue;
                            var f = ParaBuild.resolve_run (pub, cf, run);
                            smallest = double.min (smallest, f.size);
                        }
                    }
                    if (smallest < p.min_text) {
                        int page = cache.get_engine ().page_of_frame (frames[0]);
                        add (Severity.WARNING, IssueKind.PRINT_TEXT_SIZE, _("Text set at %s pt is below the %s pt minimum").printf ("%.1f".printf (smallest), "%.1f".printf (p.min_text)), page, frames[0].id);
                    }
                }
            }
        }

        public static double swatch_ink (Swatch sw, ColorManager cm) {
            double c = sw.c, m = sw.m, y = sw.y, k = sw.k;
            if (sw.model != ColorModel.CMYK) cm.rgb_to_cmyk (sw.r, sw.g, sw.b, out c, out m, out y, out k);
            double t = sw.tint_of != "" ? sw.tint / 100 : 1;
            return (c + m + y + k) * 100 * t;
        }

        public static double image_ink (ImageInfo inf, ColorManager cm) {
            int w = inf.width, h = inf.height;
            double sc = double.min (1, 160.0 / double.max (w, h));
            int sw = int.max (1, (int) (w * sc)), sh = int.max (1, (int) (h * sc));
            var small = new Cairo.ImageSurface (Cairo.Format.RGB24, sw, sh);
            var cr = new Cairo.Context (small);
            cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            cr.scale (sc, sc);
            cr.set_source_surface (inf.surface, 0, 0);
            cr.paint ();
            small.flush ();
            var cmyk = cm.surface_to_cmyk (small);
            int best = 0;
            for (int i = 0; i + 3 < cmyk.length; i += 4) best = int.max (best, cmyk[i] + cmyk[i + 1] + cmyk[i + 2] + cmyk[i + 3]);
            return best * 100.0 / 255.0;
        }

        public bool uses_transparency () {
            bool found = false;
            pub.walk ((r) => {
                var it = r.item;
                if (it.opacity < 0.999 || it.shadow.enabled || it.effects.any ()) found = true;
                foreach (var st in it.fill.stops) if (st.opacity < 0.999) found = true;
                return !found;
            });
            return found;
        }

        private void check_item (Item it, int page, LayoutCache cache, ImageStore store) {
            var g = it as GroupItem;
            if (g != null) {
                foreach (var c in g.children) check_item (c, page, cache, store);
                return;
            }
            var im = it as ImageFrame;
            if (im != null) {
                var st = ImageStore.status (pub, im);
                string name = im.link != "" ? Path.get_basename (im.link) : _("Embedded image");
                if (st == LinkStatus.MISSING) add (im.media != "" ? Severity.WARNING : Severity.ERROR, IssueKind.MISSING_LINK, _("Missing image \"%s\"").printf (name), page, im.id);
                else if (st == LinkStatus.MODIFIED) add (Severity.WARNING, IssueKind.MODIFIED_LINK, _("Image \"%s\" was modified since it was placed").printf (name), page, im.id);
                else if (st == LinkStatus.EMPTY && im.merge_field == "") add (Severity.INFO, IssueKind.EMPTY_FRAME, _("Empty image frame"), page, im.id);
                var inf = store.info (pub, im);
                if (inf != null && !inf.vector) {
                    var pl = ImageStore.place (im, inf);
                    double ppi = double.min (pl.ppi_x (), pl.ppi_y ());
                    if (ppi < error_ppi) add (Severity.ERROR, IssueKind.LOW_RES, _("\"%s\" is %d ppi, too low for print").printf (name, (int) Math.round (ppi)), page, im.id);
                    else if (ppi < min_ppi) add (Severity.WARNING, IssueKind.LOW_RES, _("\"%s\" is %d ppi, below the %d ppi target").printf (name, (int) Math.round (ppi), (int) min_ppi), page, im.id);
                    if (pub.settings.cmyk && inf.components != 4) add (Severity.WARNING, IssueKind.RGB_IMAGE, _("\"%s\" is an RGB image in a CMYK job").printf (name), page, im.id);
                }
            }
            var tb = it as TableItem;
            if (tb != null) {
                for (int r = 0; r < tb.rows; r++) for (int c = 0; c < tb.cols; c++) {
                    var cell = tb.cells[r][c];
                    if (cell.covered) continue;
                    double cw = 0, ch = 0;
                    for (int k = c; k < c + cell.col_span && k < tb.cols; k++) cw += tb.col_w[k];
                    for (int k = r; k < r + cell.row_span && k < tb.rows; k++) ch += tb.row_h[k];
                    var fr = cache.cell (cell.story, double.max (1, cw - 2 * tb.cell_inset), 100000, page);
                    if (fr.content_height > ch - 2 * tb.cell_inset + 0.5) add (Severity.ERROR, IssueKind.OVERSET, _("Overset text in table cell %d, %d").printf (r + 1, c + 1), page, tb.id);
                }
            }
        }
    }
}
