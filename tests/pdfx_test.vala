using Singularity.Apps.Publish;

string work_dir () {
    string d = Path.build_filename (Environment.get_tmp_dir (), "publish-pdfx-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

bool tool (string name) {
    return Environment.find_program_in_path (name) != null;
}

string run (string[] argv, out int status) {
    string o, e;
    status = -1;
    try {
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out o, out e, out status);
    } catch (Error err) {
        return err.message;
    }
    return o + e;
}

ShapeItem box (Publication p, double x, double y, double w, double h, string fill) {
    var s = new ShapeItem (ShapeKind.RECT);
    s.id = p.next_id ();
    s.x = x;
    s.y = y;
    s.w = w;
    s.h = h;
    s.fill = new Fill.solid (fill);
    s.layer = p.layers[0].id;
    return s;
}

uint8[] photo_png (string dir) {
    var s = new Cairo.ImageSurface (Cairo.Format.RGB24, 64, 64);
    var cr = new Cairo.Context (s);
    var g = new Cairo.Pattern.linear (0, 0, 64, 64);
    g.add_color_stop_rgb (0, 0.9, 0.2, 0.1);
    g.add_color_stop_rgb (1, 0.1, 0.4, 0.9);
    cr.set_source (g);
    cr.paint ();
    string path = Path.build_filename (dir, "photo.png");
    s.write_to_png (path);
    uint8[] data;
    try {
        FileUtils.get_data (path, out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    return data;
}

Publication job (string dir, bool transparency) {
    var s = new DocSettings ();
    s.width = 420;
    s.height = 595;
    s.set_margins (36);
    s.set_bleed (8.5);
    var p = Publication.create (s, 2);
    p.meta.title = "Validation Job";
    p.styles.find_paragraph (StyleSheet.BASIC).chars.font = "DejaVu Sans";
    p.swatches.add (new Swatch.cmyk ("PMS 021", 0, 0.53, 1, 0, true));
    p.swatches.add (new Swatch.rgb ("Screen Teal", 0.0, 0.6, 0.6));
    p.pages[0].items.add (box (p, -8.5, -8.5, 437, 120, ColorRef.swatch ("PMS 021")));
    p.pages[0].items.add (box (p, 36, 140, 160, 90, ColorRef.swatch ("Screen Teal")));
    var t = p.add_text_frame (p.pages[0].items, 36, 250, 348, 200);
    var st = p.story (t.story);
    st.insert_text (TextPos (0, 0), "Autumn Catalogue. Every font in this frame must be embedded and every colour must reach the press as CMYK or as the spot ink.");
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 220;
    im.y = 140;
    im.w = 160;
    im.h = 90;
    im.layer = p.layers[0].id;
    im.media = p.add_media (photo_png (dir), "photo.png");
    p.pages[0].items.add (im);
    var half = box (p, 60, 470, 120, 80, ColorRef.swatch ("Cyan"));
    if (transparency) half.opacity = 0.5;
    p.pages[1].items.add (half);
    p.pages[1].items.add (box (p, 200, 470, 120, 80, ColorRef.swatch ("PMS 021", 40)));
    return p;
}

string export (Publication p, ColorMode mode, string dir, string name) {
    var o = new ExportOptions ();
    o.color_mode = mode;
    o.bleed = true;
    o.crop_marks = true;
    string path = Path.build_filename (dir, name);
    try {
        new Exporter (p, o).export_pdf (path);
    } catch (Error e) {
        error (e.message);
    }
    return path;
}

Gee.ArrayList<Singularity.Pdf.Issue> engine_check (string path, string version) {
    try {
        var doc = Singularity.Pdf.Document.open_file (path);
        return Singularity.Pdf.Standards.check_pdfx (doc, version);
    } catch (Error e) {
        error (e.message);
    }
}

void external_checks (string path, string label) {
    int status;
    if (tool ("gs")) {
        string out_s = run ({ "gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-dPDFSTOPONERROR", "-dPDFSTOPONWARNING", "-sDEVICE=nullpage", path }, out status);
        if (status != 0 || out_s.down ().contains ("error") || out_s.contains ("****")) error ("%s: ghostscript rejected the file: %s", label, out_s);
        string sep = run ({ "gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=inkcov", "-o", "-", "-dFirstPage=1", "-dLastPage=1", path }, out status);
        assert (status == 0 && sep.contains ("CMYK OK"));
    }
    if (tool ("pdffonts")) {
        string fonts = run ({ "pdffonts", path }, out status);
        assert (status == 0);
        string[] lines = fonts.split ("\n");
        int listed = 0;
        for (int i = 2; i < lines.length; i++) {
            string l = lines[i].strip ();
            if (l == "") continue;
            listed++;
            string[] cols = Regex.split_simple ("\\s+", l);
            bool emb = false;
            for (int k = 0; k + 2 < cols.length; k++) if ((cols[k] == "yes" || cols[k] == "no") && (cols[k + 1] == "yes" || cols[k + 1] == "no") && (cols[k + 2] == "yes" || cols[k + 2] == "no")) {
                emb = cols[k] == "yes";
                break;
            }
            if (!emb) error ("%s: font not embedded: %s", label, l);
        }
        assert (listed > 0);
    }
    if (tool ("pdfinfo")) {
        string info = run ({ "pdfinfo", "-box", "-f", "1", "-l", "2", path }, out status);
        assert (status == 0);
        assert (info.contains ("TrimBox") && info.contains ("BleedBox"));
        assert (!info.contains ("Encrypted:      yes"));
    }
    if (tool ("mutool")) {
        string intent = run ({ "mutool", "show", path, "trailer/Root/OutputIntents/1/S" }, out status);
        assert (status == 0 && intent.contains ("/GTS_PDFX"));
        string profile = run ({ "mutool", "show", path, "trailer/Root/OutputIntents/1/DestOutputProfile/N" }, out status);
        assert (status == 0 && profile.strip ().has_suffix ("4"));
    }
}

void test_validated () {
    string dir = work_dir ();
    foreach (var mode in new ColorMode[] { ColorMode.PDFX1A, ColorMode.PDFX3, ColorMode.PDFX4 }) {
        var p = job (dir, mode == ColorMode.PDFX4);
        string name = mode == ColorMode.PDFX1A ? "x1a.pdf" : (mode == ColorMode.PDFX3 ? "x3.pdf" : "x4.pdf");
        string version = mode == ColorMode.PDFX1A ? "PDF/X-1a" : (mode == ColorMode.PDFX3 ? "PDF/X-3" : "PDF/X-4");
        string path = export (p, mode, dir, name);
        var issues = engine_check (path, version);
        foreach (var i in issues) printerr ("%s %s: %s\n", name, i.rule, i.message);
        assert (issues.size == 0);
        external_checks (path, name);
        var report = PdfxReport.verify (path, mode);
        assert (report.passed && report.problems.size == 0);
    }
}

void test_flattened () {
    string dir = work_dir ();
    foreach (var mode in new ColorMode[] { ColorMode.PDFX1A, ColorMode.PDFX3 }) {
        var p = job (dir, true);
        var shadowed = p.pages[0].items[1];
        shadowed.shadow.enabled = true;
        string name = mode == ColorMode.PDFX1A ? "x1a-flat.pdf" : "x3-flat.pdf";
        string path = export (p, mode, dir, name);
        var issues = engine_check (path, PdfxReport.version_of (mode));
        foreach (var i in issues) printerr ("%s %s: %s\n", name, i.rule, i.message);
        assert (issues.size == 0);
        external_checks (path, name);
        if (tool ("pdfimages")) {
            int st;
            string list = run ({ "pdfimages", "-list", path }, out st);
            assert (st == 0 && list.contains ("cmyk"));
            assert (!list.contains ("smask"));
        }
        if (tool ("pdftoppm")) {
            int st;
            string png = Path.build_filename (dir, name + "-2");
            run ({ "pdftoppm", "-f", "2", "-l", "2", "-r", "36", "-png", "-singlefile", path, png }, out st);
            assert (st == 0);
            try {
                var pb = new Gdk.Pixbuf.from_file (png + ".png");
                double s = 36.0 / 72.0;
                int x = (int) ((8.5 + 120) * s), y = (int) ((8.5 + 510) * s);
                unowned uint8[] px = pb.get_pixels_with_length ();
                int at = y * pb.rowstride + x * pb.n_channels;
                assert (px[at] < 200 && px[at + 2] > 180);
                assert (px[at] > 60);
            } catch (Error e) {
                error (e.message);
            }
        }
    }
}

void test_rejects () {
    string dir = work_dir ();
    var p = job (dir, true);
    string rgb = export (p, ColorMode.RGB, dir, "rgb.pdf");
    var issues = engine_check (rgb, "PDF/X-4");
    assert (issues.size >= 2);
    var report = PdfxReport.verify (rgb, ColorMode.PDFX4);
    assert (!report.passed && report.problems.size >= 2);
    var x1a_from_rgb = engine_check (rgb, "PDF/X-1a");
    bool rgb_found = false;
    foreach (var i in x1a_from_rgb) if (i.message.contains ("RGB")) rgb_found = true;
    assert (rgb_found);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/pdfx/validated", test_validated);
    Test.add_func ("/pdfx/flattened", test_flattened);
    Test.add_func ("/pdfx/rejects", test_rejects);
    return Test.run ();
}
