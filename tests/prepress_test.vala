using Singularity.Apps.Publish;

string outdir () {
    string d = Path.build_filename (Environment.get_tmp_dir (), "publish-prepress-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

bool has_tool (string name) {
    return Environment.find_program_in_path (name) != null;
}

string run (string[] argv) {
    string stdout_s, stderr_s;
    int status;
    try {
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out stdout_s, out stderr_s, out status);
    } catch (Error e) {
        return "";
    }
    return stdout_s + stderr_s;
}

ShapeItem rect (Publication p, double x, double y, double w, double h, string fill) {
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

uint8[] red_png () {
    var s = new Cairo.ImageSurface (Cairo.Format.RGB24, 16, 16);
    var cr = new Cairo.Context (s);
    cr.set_source_rgb (1, 0, 0);
    cr.paint ();
    string p = Path.build_filename (outdir (), "red.png");
    s.write_to_png (p);
    uint8[] data;
    try {
        FileUtils.get_data (p, out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    return data;
}

Publication sample () {
    var s = new DocSettings ();
    s.width = 300;
    s.height = 200;
    s.set_margins (20);
    s.set_bleed (9);
    var p = Publication.create (s, 2);
    p.meta.title = "Prepress Sample";
    var spot = new Swatch.cmyk ("PMS Orange", 0, 0.6, 1, 0, true);
    p.swatches.add (spot);
    p.pages[0].items.add (rect (p, -9, -9, 150, 100, ColorRef.swatch ("PMS Orange")));
    p.pages[0].items.add (rect (p, 150, 0, 159, 209, ColorRef.swatch ("Cyan")));
    var g = rect (p, 20, 120, 100, 40, "");
    g.fill = new Fill.linear (ColorRef.swatch ("Magenta"), ColorRef.swatch ("Yellow"), 0);
    p.pages[0].items.add (g);
    var t = p.add_text_frame (p.pages[0].items, 160, 20, 120, 80);
    var st = p.story (t.story);
    st.insert_text (TextPos (0, 0), "BLACK TEXT OVER CYAN");
    st.apply_chars (TextPos (0, 0), st.end_pos (), (r) => {
        r.fmt.size = 28;
        r.fmt.color = ColorRef.BLACK;
    });
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 200;
    im.y = 120;
    im.w = 60;
    im.h = 60;
    im.layer = p.layers[0].id;
    im.media = p.add_media (red_png (), "red.png");
    p.pages[0].items.add (im);
    p.pages[1].items.add (rect (p, 50, 50, 100, 100, ColorRef.swatch ("PMS Orange", 50)));
    return p;
}

string text_of (uint8[] d) {
    var sb = new StringBuilder ();
    foreach (uint8 c in d) sb.append_c (c >= 32 && c < 127 || c == '\n' ? (char) c : '.');
    return sb.str;
}

void test_sentinel () {
    var p = sample ();
    var cm = ColorManager.for_settings (p.settings);
    var so = new SentinelOutput (p, cm);
    bool op;
    var c = so.map (p, ColorRef.swatch ("Cyan", 40), Rgba (0, 0, 0, 0.5));
    assert (Math.fabs (c.a - 0.5) < 1e-9);
    var ink = so.decode (c.r, c.g, c.b, out op);
    assert (ink != null && ink.kind == InkKind.PROCESS);
    assert (Math.fabs (ink.c - 0.4) < 1e-6 && ink.m < 1e-9 && ink.k < 1e-9);
    assert (!op);
    var b = so.map (p, ColorRef.BLACK, Rgba (0, 0, 0, 1));
    ink = so.decode (b.r, b.g, b.b, out op);
    assert (ink != null && Math.fabs (ink.k - 1) < 1e-9 && op);
    uint16 r16 = (uint16) Math.round (b.r * 65535), g16 = (uint16) Math.round (b.g * 65535), b16 = (uint16) Math.round (b.b * 65535);
    ink = so.decode (r16 / 65535.0, g16 / 65535.0, b16 / 65535.0, out op);
    assert (ink != null && op);
    var s = so.map (p, ColorRef.swatch ("PMS Orange", 30), Rgba (0, 0, 0, 1));
    ink = so.decode (s.r, s.g, s.b, out op);
    assert (ink.kind == InkKind.SPOT && ink.spot == "PMS Orange" && Math.fabs (ink.tint - 0.3) < 1e-6 && Math.fabs (ink.y - 1) < 1e-9);
    var reg = so.map (p, "swatch:Registration", Rgba (0, 0, 0, 1));
    ink = so.decode (reg.r, reg.g, reg.b, out op);
    assert (ink.kind == InkKind.ALL);
    so.overprint = true;
    var o = so.map (p, ColorRef.swatch ("Magenta"), Rgba (0, 0, 0, 1));
    so.decode (o.r, o.g, o.b, out op);
    assert (op);
    assert (so.decode (1, 1, 1, out op) == null);
    var plates = PrepressExport.plates (p);
    assert (plates.contains ("Cyan") && plates.contains ("PMS Orange") && plates.size == 5);
}

void test_color_manager () {
    var p = sample ();
    var cm = ColorManager.for_settings (p.settings);
    assert (cm.profile_data ().length > 128);
    var data = cm.profile_data ();
    assert (data[36] == 'a' && data[37] == 'c' && data[38] == 's' && data[39] == 'p');
    assert (data[16] == 'C' && data[17] == 'M' && data[18] == 'Y' && data[19] == 'K');
    double c, m, y, k;
    cm.rgb_to_cmyk (1, 1, 1, out c, out m, out y, out k);
    assert (c + m + y + k < 0.05);
    cm.rgb_to_cmyk (0, 0, 0, out c, out m, out y, out k);
    assert (k > 0.8);
    cm.rgb_to_cmyk (0, 1, 1, out c, out m, out y, out k);
    assert (c > 0.6 && m < 0.2 && y < 0.2);
    var w = cm.cmyk_to_rgb (0, 0, 0, 0);
    assert (w.r > 0.95 && w.g > 0.95 && w.b > 0.95);
    var cy = cm.cmyk_to_rgb (1, 0, 0, 0);
    assert (cy.r < 0.3 && cy.b > 0.7);
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 2, 1);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 0, 0);
    cr.rectangle (0, 0, 1, 1);
    cr.fill ();
    var px = cm.surface_to_cmyk (surf);
    assert (px.length == 8);
    assert (px[1] > 180 && px[2] > 180 && px[0] < 60);
    assert (px[4] < 10 && px[5] < 10 && px[6] < 10 && px[7] < 10);
    assert (ColorManager.get ("/nonexistent.icc", 1).description () == ColorManager.GENERIC_NAME);
    foreach (var info in ColorManager.cmyk_profiles ()) {
        var real = ColorManager.get (info.path, 0);
        if (real.has_icc ()) {
            real.rgb_to_cmyk (0, 0, 0, out c, out m, out y, out k);
            assert (k > 0.85 || c + m + y > 2.5);
        }
    }
}

PdfFile export (Publication p, ColorMode mode, string name, out uint8[] bytes, bool separations = false) {
    var o = new ExportOptions ();
    o.color_mode = mode;
    o.separations = separations;
    o.bleed = true;
    o.crop_marks = true;
    string path = Path.build_filename (outdir (), name);
    try {
        var ex = new Exporter (p, o);
        ex.export_pdf (path);
        FileUtils.get_data (path, out bytes);
        return PdfFile.parse (bytes);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

string page_content (PdfFile f, PdfObj page) {
    var e = f.entry_of (page.get ("Contents"));
    assert (e != null);
    try {
        return text_of (f.decoded (e));
    } catch (Error err) {
        assert_not_reached ();
    }
}

void test_pdfx4 () {
    var p = sample ();
    uint8[] bytes;
    var f = export (p, ColorMode.PDFX4, "x4.pdf", out bytes);
    assert (text_of (bytes[0:9]) == "%PDF-1.6\n");
    var pages = f.pages ();
    assert (pages.size == 2);
    foreach (var pg in pages) {
        var media = f.deref (pg.get ("MediaBox"));
        var trim = f.deref (pg.get ("TrimBox"));
        var bleed = f.deref (pg.get ("BleedBox"));
        assert (trim.items.size == 4 && bleed.items.size == 4);
        double tw = trim.items[2].num - trim.items[0].num, th = trim.items[3].num - trim.items[1].num;
        assert (Math.fabs (tw - 300) < 0.01 && Math.fabs (th - 200) < 0.01);
        assert (Math.fabs (trim.items[0].num - bleed.items[0].num - 9) < 0.01);
        assert (Math.fabs (bleed.items[3].num - trim.items[3].num - 9) < 0.01);
        assert (bleed.items[0].num >= media.items[0].num && bleed.items[2].num <= media.items[2].num);
        var g = f.deref (pg.get ("Group"));
        if (g.type == PdfType.DICT) assert (g.name_of ("CS") != "DeviceRGB");
    }
    var root = f.deref (f.trailer.get ("Root"));
    var intents = f.deref (root.get ("OutputIntents"));
    assert (intents.items.size == 1);
    var intent = f.deref (intents.items[0]);
    assert (intent.name_of ("S") == "GTS_PDFX");
    var icc = f.entry_of (intent.get ("DestOutputProfile"));
    assert (icc != null && (int) icc.obj.get ("N").num == 4);
    var meta = f.entry_of (root.get ("Metadata"));
    assert (meta != null && text_of (meta.stream).contains ("<pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>"));
    var info = f.deref (f.trailer.get ("Info"));
    assert (info.name_of ("Trapped") == "False");
    assert (f.deref (f.trailer.get ("ID")).items.size == 2);
    string c0 = page_content (f, pages[0]);
    assert (!c0.contains (" rg") && !c0.contains (" RG"));
    assert (c0.contains (" k") || c0.contains (" k\n"));
    assert (c0.contains ("/CSs0 cs 1 scn"));
    assert (c0.contains ("/GSop gs"));
    assert (c0.contains ("1 1 1 1 K") || c0.contains ("/CSall CS 1 SCN") || c0.contains ("/CSall CS"));
    string c1 = page_content (f, pages[1]);
    assert (c1.contains ("/CSs0 cs 0.5 scn"));
    var res = f.deref (pages[0].get ("Resources"));
    var cs = f.deref (f.deref (res.get ("ColorSpace")).get ("CSs0"));
    assert (cs.items.size == 4 && cs.items[0].name == "Separation" && cs.items[1].name == "PMS Orange" && cs.items[2].name == "DeviceCMYK");
    var gs = f.deref (f.deref (res.get ("ExtGState")).get ("GSop"));
    assert (gs.get ("OP").bval && gs.get ("op").bval && (int) gs.get ("OPM").num == 1);
    int images = 0, rgb_images = 0, shadings = 0, rgb_shadings = 0;
    foreach (var e in f.objs.values) {
        var o = e.obj;
        if (o.type != PdfType.DICT) continue;
        if (o.name_of ("Subtype") == "Image") {
            images++;
            if (f.deref (o.get ("ColorSpace")).is_name ("DeviceRGB")) rgb_images++;
            if (f.deref (o.get ("ColorSpace")).is_name ("DeviceCMYK")) {
                var px = f.decoded (e);
                assert (px != null && px.length >= 4 && px[1] > 150 && px[2] > 150);
            }
        }
        if (o.get ("ShadingType") != null) {
            shadings++;
            if (f.deref (o.get ("ColorSpace")).is_name ("DeviceRGB")) rgb_shadings++;
        }
    }
    assert (images >= 1 && rgb_images == 0);
    assert (shadings >= 1 && rgb_shadings == 0);
    string path = Path.build_filename (outdir (), "x4-check.pdf");
    try {
        FileUtils.set_data (path, bytes);
    } catch (Error e) {
        assert_not_reached ();
    }
    if (has_tool ("pdfinfo")) {
        string out_s = run ({ "pdfinfo", "-box", path });
        assert (out_s.contains ("TrimBox:"));
        assert (out_s.contains ("BleedBox:"));
        assert (out_s.contains ("Pages:           2"));
    } else {
        print ("pdfinfo missing, box check skipped\n");
    }
    if (has_tool ("mutool")) {
        string out_s = run ({ "mutool", "info", path });
        assert (out_s.contains ("Pages: 2"));
        assert (!out_s.down ().contains ("error"));
    }
    if (has_tool ("gs")) check_separations_with_gs (path);
    else print ("gs missing, separation check skipped\n");
}

uint8 plate_pixel (string file, int x, int y) {
    try {
        var pb = new Gdk.Pixbuf.from_file (file);
        unowned uint8[] px = pb.get_pixels_with_length ();
        return px[y * pb.rowstride + x * pb.n_channels];
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void check_separations_with_gs (string pdf) {
    string dir = outdir ();
    string base_name = Path.build_filename (dir, "sep.tif");
    run ({ "gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=tiffsep", "-r36", "-dFirstPage=1", "-dLastPage=1", "-dUseTrimBox", "-sOutputFile=" + base_name, pdf });
    string cyan = Path.build_filename (dir, "sep(Cyan).tif");
    string black = Path.build_filename (dir, "sep(Black).tif");
    string spot = Path.build_filename (dir, "sep(PMS Orange).tif");
    string magenta = Path.build_filename (dir, "sep(Magenta).tif");
    assert (FileUtils.test (cyan, FileTest.EXISTS));
    assert (FileUtils.test (spot, FileTest.EXISTS));
    uint8 paper = plate_pixel (cyan, 5, 95);
    uint8 inked = plate_pixel (cyan, 145, 95);
    assert (paper != inked);
    uint8 spot_in = plate_pixel (spot, 30, 20);
    uint8 spot_out = plate_pixel (spot, 145, 95);
    assert (spot_in != spot_out);
    assert (plate_pixel (magenta, 30, 20) == plate_pixel (magenta, 5, 95));
    var pb = new Gdk.Pixbuf.from_file (black);
    int bx = -1, by = -1;
    unowned uint8[] px = pb.get_pixels_with_length ();
    uint8 black_paper = px[0];
    for (int y = 10; y < 45 && bx < 0; y++) for (int x = 80; x < 140; x++) {
        if (px[y * pb.rowstride + x * pb.n_channels] != black_paper) {
            bx = x;
            by = y;
            break;
        }
    }
    assert (bx >= 0);
    assert (plate_pixel (cyan, bx, by) == inked);
}

void test_pdfx1a () {
    var p = sample ();
    uint8[] bytes;
    var f = export (p, ColorMode.PDFX1A, "x1a.pdf", out bytes);
    assert (text_of (bytes[0:9]) == "%PDF-1.4\n");
    var info = f.deref (f.trailer.get ("Info"));
    assert (text_of (info.get ("GTS_PDFXVersion").raw) == "(PDF/X-1:2003)");
    assert (text_of (info.get ("GTS_PDFXConformance").raw) == "(PDF/X-1a:2003)");
    var root = f.deref (f.trailer.get ("Root"));
    assert (f.deref (root.get ("OutputIntents")).items.size == 1);
    uint8[] cb;
    var cf = export (p, ColorMode.CMYK, "cmyk.pdf", out cb);
    var croot = cf.deref (cf.trailer.get ("Root"));
    assert (croot.get ("OutputIntents") == null);
    assert (!page_content (cf, cf.pages ()[0]).contains (" rg"));
}

void test_separations () {
    var p = sample ();
    uint8[] bytes;
    var f = export (p, ColorMode.RGB, "sep.pdf", out bytes, true);
    assert (f.pages ().size == 2 * 5);
    foreach (var pg in f.pages ()) assert (pg.get ("TrimBox") != null);
    var o = new ExportOptions ();
    o.separations = true;
    o.plates.add ("Black");
    o.plates.add ("PMS Orange");
    string path = Path.build_filename (outdir (), "sep2.pdf");
    try {
        int n = PrepressExport.export_pdf (p, o, path);
        assert (n == 4);
        FileUtils.get_data (path, out bytes);
        assert (PdfFile.parse (bytes).pages ().size == 4);
    } catch (Error e) {
        assert_not_reached ();
    }
    var plate = PrepressExport.plate_publication (p, "PMS Orange");
    var s = new Cairo.ImageSurface (Cairo.Format.ARGB32, 300, 200);
    var cr = new Cairo.Context (s);
    var r = new Renderer (plate);
    r.opts.print = true;
    r.draw_page (cr, 0, true);
    s.flush ();
    unowned uint8[] d = s.get_data ();
    int inside = 30 * s.get_stride () + 30 * 4;
    int outside = 150 * s.get_stride () + 200 * 4;
    assert (d[inside] < 20);
    assert (d[outside] > 235);
    var kp = PrepressExport.plate_publication (p, "Black");
    s = new Cairo.ImageSurface (Cairo.Format.ARGB32, 300, 200);
    cr = new Cairo.Context (s);
    r = new Renderer (kp);
    r.opts.print = true;
    r.draw_page (cr, 0, true);
    s.flush ();
    d = s.get_data ();
    assert (d[inside] > 235);
}

void test_pdf_roundtrip () {
    var f = new PdfFile ();
    var d = PdfObj.dict ();
    d.set ("Type", PdfObj.of_name ("Catalog"));
    d.set ("Name", PdfObj.of_name ("PMS 021 C"));
    d.set ("T", PdfObj.of_text ("Caf\xc3\xa9 (x)"));
    int n = f.add (d);
    f.trailer.set ("Root", PdfObj.of_ref (n));
    var bytes = f.serialize ("1.4");
    try {
        var g = PdfFile.parse (bytes);
        var root = g.deref (g.trailer.get ("Root"));
        assert (root.name_of ("Name") == "PMS 021 C");
        assert (text_of (root.get ("T").raw).has_prefix ("<FEFF"));
    } catch (Error e) {
        assert_not_reached ();
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/prepress/sentinel", test_sentinel);
    Test.add_func ("/prepress/color-manager", test_color_manager);
    Test.add_func ("/prepress/roundtrip", test_pdf_roundtrip);
    Test.add_func ("/prepress/pdfx4", test_pdfx4);
    Test.add_func ("/prepress/pdfx1a", test_pdfx1a);
    Test.add_func ("/prepress/separations", test_separations);
    Test.run ();
}
