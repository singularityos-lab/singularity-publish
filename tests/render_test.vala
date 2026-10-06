using Singularity.Apps.Publish;

string outdir () {
    string d = Environment.get_variable ("PUBLISH_TEST_OUT") ?? Path.build_filename (Environment.get_tmp_dir (), "publish-render-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

uint8[] pixel (Cairo.ImageSurface s, int x, int y) {
    s.flush ();
    unowned uint8[] d = s.get_data ();
    int i = y * s.get_stride () + x * 4;
    return { d[i + 2], d[i + 1], d[i], d[i + 3] };
}

bool close_rgb (uint8[] px, int r, int g, int b, int tol = 12) {
    return (px[0] - r).abs () <= tol && (px[1] - g).abs () <= tol && (px[2] - b).abs () <= tol;
}

Cairo.ImageSurface render (Publication p, int page, double scale = 1) {
    int w = (int) (p.settings.width * scale), h = (int) (p.settings.height * scale);
    var s = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
    var cr = new Cairo.Context (s);
    cr.scale (scale, scale);
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_page (cr, page, true);
    return s;
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

Publication small () {
    var s = new DocSettings ();
    s.width = 200;
    s.height = 100;
    s.set_margins (10);
    return Publication.create (s, 2);
}

void test_fills_and_layers () {
    var p = small ();
    p.pages[0].items.add (rect (p, 0, 0, 50, 50, "#ff0000"));
    var top = rect (p, 25, 25, 50, 50, "#0000ff");
    p.pages[0].items.add (top);
    var s = render (p, 0);
    assert (close_rgb (pixel (s, 10, 10), 255, 0, 0));
    assert (close_rgb (pixel (s, 40, 40), 0, 0, 255));
    assert (close_rgb (pixel (s, 150, 80), 255, 255, 255));
    var back = new Layer (p.next_id (), "Back");
    p.layers.insert (0, back);
    top.layer = back.id;
    s = render (p, 0);
    assert (close_rgb (pixel (s, 40, 40), 255, 0, 0));
    back.printable = false;
    s = render (p, 0);
    assert (close_rgb (pixel (s, 60, 60), 255, 255, 255));
    top.opacity = 0.5;
    back.printable = true;
    top.layer = p.layers[1].id;
    s = render (p, 0);
    assert (close_rgb (pixel (s, 40, 40), 127, 0, 127, 20));
}

void test_gradient_shadow () {
    var p = small ();
    var g = rect (p, 0, 0, 100, 20, "");
    g.fill = new Fill.linear ("#000000", "#ffffff", 0);
    p.pages[0].items.add (g);
    var sh = rect (p, 120, 20, 40, 40, "#00ff00");
    sh.shadow.enabled = true;
    sh.shadow.dx = 10;
    sh.shadow.dy = 10;
    sh.shadow.blur = 2;
    sh.shadow.opacity = 1;
    p.pages[0].items.add (sh);
    var s = render (p, 0);
    var left = pixel (s, 5, 10), right = pixel (s, 95, 10);
    assert (left[0] < 40 && right[0] > 215);
    assert (pixel (s, 50, 10)[0] > 90 && pixel (s, 50, 10)[0] < 165);
    var shadow = pixel (s, 165, 65);
    assert (shadow[0] < 120 && shadow[1] < 120);
    assert (close_rgb (pixel (s, 140, 40), 0, 255, 0));
}

void test_image_fit () {
    var p = small ();
    var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 20, 10);
    pb.fill ((uint32) 0xff0000ff);
    uint8[] png;
    try {
        pb.save_to_buffer (out png, "png");
    } catch (Error e) {
        assert_not_reached ();
    }
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.media = p.add_media (png, "r.png");
    im.x = 0;
    im.y = 0;
    im.w = 40;
    im.h = 40;
    im.fit = FitMode.FIT;
    im.layer = p.layers[0].id;
    p.pages[0].items.add (im);
    var s = render (p, 0);
    assert (close_rgb (pixel (s, 20, 20), 255, 0, 0));
    assert (close_rgb (pixel (s, 20, 3), 255, 255, 255));
    im.fit = FitMode.FILL;
    s = render (p, 0);
    assert (close_rgb (pixel (s, 20, 3), 255, 0, 0));
    im.shape_ellipse = true;
    s = render (p, 0);
    assert (close_rgb (pixel (s, 2, 2), 255, 255, 255));
    assert (close_rgb (pixel (s, 20, 20), 255, 0, 0));
}

void test_text_draws () {
    var p = small ();
    var f = p.add_text_frame (p.pages[0].items, 10, 10, 180, 80);
    var st = p.story (f.story);
    st.insert_text (TextPos (0, 0), "HHHHHHHHHHHHHHHHHHHH");
    st.apply_chars (TextPos (0, 0), st.end_pos (), (r) => {
        r.fmt.size = 30;
        r.fmt.color = "#0000ff";
    });
    var s = render (p, 0);
    int blue = 0;
    for (int x = 10; x < 190; x++) for (int y = 10; y < 50; y++) {
        var px = pixel (s, x, y);
        if (px[2] > 200 && px[0] < 80) blue++;
    }
    assert (blue > 300);
}

void test_pdf_bleed_marks () {
    var p = small ();
    p.settings.set_bleed (9);
    p.pages[0].items.add (rect (p, -9, -9, 218, 118, "#00ffff"));
    var ex = new Exporter (p);
    ex.opts.crop_marks = true;
    ex.opts.reg_marks = true;
    ex.opts.page_info = true;
    var sheets = ex.sheets ();
    assert (sheets.size == 2);
    double m = ex.marks_margin ();
    assert ((sheets[0].w - (218 + 2 * m)).abs () < 0.01);
    string pdf = Path.build_filename (outdir (), "bleed.pdf");
    try {
        assert (ex.export_pdf (pdf) == 2);
    } catch (Error e) {
        assert_not_reached ();
    }
    uint8[] data;
    try {
        FileUtils.get_data (pdf, out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    string head = Bin.head (data, data.length);
    assert (head.has_prefix ("%PDF-1.4"));
    ex.opts.dpi = 72;
    var surf = ex.render_sheet (sheets[0]);
    int cx = (int) (m + 9 + 100);
    assert (close_rgb (pixel (surf, cx, (int) (m + 2)), 0, 255, 255));
    assert (close_rgb (pixel (surf, cx + 30, (int) (m - 4)), 255, 255, 255));
    ex.opts.bleed = false;
    var ns = ex.sheets ();
    assert ((ns[0].w - (200 + 2 * m)).abs () < 0.01);
}

void test_nup_booklet () {
    var s = new DocSettings ();
    s.width = 85 * Units.PT_PER_MM;
    s.height = 55 * Units.PT_PER_MM;
    var p = Publication.create (s, 2);
    var ex = new Exporter (p);
    ex.opts.impose = ImposeMode.NUP;
    ex.opts.cols = 2;
    ex.opts.rows = 5;
    ex.opts.step_repeat = true;
    ex.opts.bleed = false;
    var sheets = ex.sheets ();
    assert (sheets.size == 2);
    assert (sheets[0].slots.size == 10);
    foreach (var sl in sheets[0].slots) assert (sl.page == 0);
    foreach (var sl in sheets[1].slots) assert (sl.page == 1);
    assert (sheets[0].slots[1].x > sheets[0].slots[0].x);
    assert (sheets[0].slots[2].y > sheets[0].slots[0].y);
    foreach (var sl in sheets[0].slots) assert (sl.x >= 0 && sl.x + sl.w <= ex.opts.sheet_w + 0.01);
    p.settings.set_bleed (3 * Units.PT_PER_MM);
    ex.opts.bleed = true;
    ex.opts.crop_marks = true;
    var bs0 = ex.sheets ();
    assert (bs0[0].slots[0].scale == 1);
    assert ((bs0[0].slots[1].x - bs0[0].slots[0].x - p.settings.width).abs () < 0.01);
    string cards = Path.build_filename (outdir (), "cards.pdf");
    try {
        ex.export_pdf (cards);
    } catch (Error e) {
        assert_not_reached ();
    }
    var b = Publication.create (null, 6);
    var bx = new Exporter (b);
    bx.opts.impose = ImposeMode.BOOKLET;
    bx.opts.sheet_w = 842;
    bx.opts.sheet_h = 595;
    var bs = bx.sheets ();
    assert (bs.size == 4);
    assert (bs[0].slots[0].page == -1 || bs[0].slots.size == 1 || bs[0].slots[0].page == 7);
    assert (bs[0].slots[bs[0].slots.size - 1].page == 0);
    assert (bs[1].slots[0].page == 1);
    assert (bs[2].slots[0].page == 5 || bs[2].slots.size == 2);
    var pages = new Gee.ArrayList<int> ();
    foreach (var sh in bs) foreach (var sl in sh.slots) pages.add (sl.page);
    for (int i = 0; i < 6; i++) assert (pages.contains (i));
    string pdf = Path.build_filename (outdir (), "booklet.pdf");
    try {
        assert (bx.export_pdf (pdf) == 4);
    } catch (Error e) {
        assert_not_reached ();
    }
}

void test_spreads_and_ranges () {
    var p = Publication.create (null, 5);
    p.settings.facing = true;
    var ex = new Exporter (p);
    ex.opts.spreads = true;
    ex.opts.bleed = false;
    var sh = ex.sheets ();
    assert (sh.size == 3);
    assert (sh[1].slots.size == 2);
    assert ((sh[1].w - 2 * p.settings.width).abs () < 0.01);
    var r = Exporter.parse_ranges ("1-2, 5, 9, 3-", 5);
    assert (r.size == 5 && r[0] == 0 && r[2] == 4 && r[3] == 2);
    ex.opts.spreads = false;
    ex.opts.ranges = "2-3";
    assert (ex.sheets ().size == 2);
}

void test_raster_export () {
    var p = small ();
    p.pages[0].items.add (rect (p, 0, 0, 200, 100, "#336699"));
    var ex = new Exporter (p);
    ex.opts.dpi = 144;
    string d = outdir ();
    try {
        var files = ex.export_images (d, "page", "png");
        assert (files.size == 2);
        var pb = new Gdk.Pixbuf.from_file (files[0]);
        assert (pb.width == 400 && pb.height == 200);
        var jf = ex.export_images (d, "page", "jpeg");
        assert (jf[0].has_suffix (".jpg"));
        var jp = new Gdk.Pixbuf.from_file (jf[0]);
        assert (jp.width == 400);
        uint8[] data;
        FileUtils.get_data (jf[0], out data);
        assert (data[0] == 0xFF && data[1] == 0xD8);
        foreach (var f in files) FileUtils.remove (f);
        foreach (var f in jf) FileUtils.remove (f);
    } catch (Error e) {
        assert_not_reached ();
    }
    var th = ex.thumbnail (0, 100);
    assert (th.get_width () == 100 && th.get_height () == 50);
}

void test_master_items_render () {
    var p = small ();
    p.master ("A").items.add (rect (p, 0, 90, 200, 10, "#ff00ff"));
    var s = render (p, 1);
    assert (close_rgb (pixel (s, 100, 95), 255, 0, 255));
    p.pages[1].hide_master = true;
    s = render (p, 1);
    assert (close_rgb (pixel (s, 100, 95), 255, 255, 255));
}

void test_table_render () {
    var p = small ();
    var t = new TableItem (2, 2);
    t.id = p.next_id ();
    t.x = 10;
    t.y = 10;
    t.w = 100;
    t.h = 40;
    t.header_fill = "#ff0000";
    t.alt_fill = "";
    t.init_cells (p);
    t.cells[1][1].fill = "#00ff00";
    t.layer = p.layers[0].id;
    p.pages[0].items.add (t);
    var s = render (p, 0);
    assert (close_rgb (pixel (s, 30, 20), 255, 0, 0));
    assert (close_rgb (pixel (s, 90, 45), 0, 255, 0));
    assert (close_rgb (pixel (s, 30, 45), 255, 255, 255));
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/render/fills-layers", test_fills_and_layers);
    Test.add_func ("/render/gradient-shadow", test_gradient_shadow);
    Test.add_func ("/render/image-fit", test_image_fit);
    Test.add_func ("/render/text", test_text_draws);
    Test.add_func ("/render/pdf-bleed-marks", test_pdf_bleed_marks);
    Test.add_func ("/render/nup-booklet", test_nup_booklet);
    Test.add_func ("/render/spreads-ranges", test_spreads_and_ranges);
    Test.add_func ("/render/raster-export", test_raster_export);
    Test.add_func ("/render/master-items", test_master_items_render);
    Test.add_func ("/render/table", test_table_render);
    return Test.run ();
}
