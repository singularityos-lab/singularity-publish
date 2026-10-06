using Singularity.Apps.Publish;

string outdir () {
    string d = Path.build_filename (Environment.get_tmp_dir (), "publish-features-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (d, 0700);
    return d;
}

string lorem (int n) {
    string[] words = { "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dogs", "while", "printing", "presses", "hum", "quietly", "along" };
    var sb = new StringBuilder ();
    for (int i = 0; i < n; i++) {
        if (i > 0) sb.append (" ");
        sb.append (words[i % words.length]);
    }
    return sb.str;
}

Publication base_pub (int pages = 1) {
    var s = new DocSettings ();
    s.width = 300;
    s.height = 300;
    s.set_margins (20);
    var p = Publication.create (s, pages);
    p.styles.find_paragraph (StyleSheet.BASIC).para.hyphenate = 0;
    p.styles.find_paragraph (StyleSheet.BASIC).chars.font = "DejaVu Sans";
    p.styles.find_paragraph ("Body Text").para.align = (int) TextAlign.LEFT;
    return p;
}

void fill (Publication p, TextFrame f, int paras, int words) {
    var s = p.story (f.story);
    s.paras.clear ();
    for (int i = 0; i < paras; i++) s.paras.add (new Paragraph.with_text (lorem (words), "Body Text"));
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

Cairo.ImageSurface render (Publication p, int page = 0) {
    var s = new Cairo.ImageSurface (Cairo.Format.ARGB32, (int) p.settings.width, (int) p.settings.height);
    var cr = new Cairo.Context (s);
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_page (cr, page, true);
    s.flush ();
    return s;
}

uint8[] px (Cairo.ImageSurface s, int x, int y) {
    unowned uint8[] d = s.get_data ();
    int i = y * s.get_stride () + x * 4;
    return { d[i + 2], d[i + 1], d[i], d[i + 3] };
}

bool white (uint8[] c) {
    return c[0] > 245 && c[1] > 245 && c[2] > 245;
}

int count_non_white (Cairo.ImageSurface s, int x0, int y0, int x1, int y1) {
    int n = 0;
    for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) if (!white (px (s, x, y))) n++;
    return n;
}

void test_roundtrip_new_fields () {
    var p = base_pub (2);
    var sh = rect (p, 10, 10, 80, 60, ColorRef.swatch ("Cyan"));
    sh.alt_text = "A blue box";
    sh.link = "https://example.org/a b";
    sh.overprint_fill = true;
    sh.effects.glow = true;
    sh.effects.glow_size = 7;
    sh.effects.soft_edges = 4;
    sh.effects.reflection = true;
    sh.effects.bevel = true;
    sh.border_art.design = "stars";
    sh.border_art.size = 12;
    sh.wrap = WrapMode.THROUGH;
    sh.wrap_points.add (Point (0, 0));
    sh.wrap_points.add (Point (1, 0.2));
    sh.wrap_points.add (Point (0.5, 1));
    sh.fill.kind = FillKind.PATTERN;
    sh.fill.pattern = "dots-50";
    sh.fill.bg_color = ColorRef.swatch ("Yellow");
    p.pages[0].items.add (sh);
    var wa = new WordArtItem ();
    wa.id = p.next_id ();
    wa.text = "Hello";
    wa.warp = WarpKind.ARCH_UP;
    wa.warp_amount = 0.7;
    wa.x = 10;
    wa.y = 100;
    wa.w = 200;
    wa.h = 60;
    wa.fill = new Fill.solid (ColorRef.swatch ("Red"));
    p.pages[0].items.add (wa);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.brightness = 0.25;
    im.contrast = -0.5;
    im.recolor = 2;
    im.clip_shape = "heart";
    im.alt_decorative = true;
    p.pages[1].items.add (im);
    var t = p.add_text_frame (p.pages[0].items, 20, 200, 200, 60);
    t.autofit = 1;
    t.vertical = true;
    var st = p.story (t.story);
    st.insert_text (TextPos (0, 0), "Linked text");
    st.apply_chars (TextPos (0, 0), st.end_pos (), (r) => {
        r.fmt.link = "bookmark:Intro";
        r.fmt.outline_color = ColorRef.BLACK;
        r.fmt.outline_width = 0.8;
        r.fmt.text_shadow = 1;
        r.fmt.emboss = 2;
    });
    p.bookmarks.add (new Bookmark ("Intro", 1, 30, 40));
    p.business.set_name = "Main";
    p.business.set ("name", "Ada Lovelace");
    p.color_scheme = "Aqua";
    p.font_scheme = "Modern";
    p.macros.add (new MacroDef ("Tidy", "replace \"a\" \"b\"\n"));
    p.merge.fields.add ("Name");
    p.merge.records.add (new Gee.ArrayList<string>.wrap ({ "x" }));
    p.merge.filters.add (new MergeFilter ("Name", FilterOp.CONTAINS, "x", false));
    p.merge.sorts.add (new MergeSort ("Name", true));
    p.merge.excluded.add (0);
    p.merge.email_field = "Name";
    p.settings.icc_profile = "/nowhere.icc";
    p.settings.intent = 0;
    p.settings.overprint_black = false;
    Publication q;
    try {
        q = NativeFormat.from_xml (NativeFormat.to_xml (p));
    } catch (Error e) {
        assert_not_reached ();
    }
    var s2 = (ShapeItem) q.pages[0].items[0];
    assert (s2.alt_text == "A blue box" && s2.link == "https://example.org/a b" && s2.overprint_fill);
    assert (s2.effects.glow && s2.effects.glow_size == 7 && s2.effects.soft_edges == 4 && s2.effects.reflection && s2.effects.bevel);
    assert (s2.border_art.design == "stars" && s2.border_art.size == 12);
    assert (s2.wrap == WrapMode.THROUGH && s2.wrap_points.size == 3);
    assert (s2.fill.kind == FillKind.PATTERN && s2.fill.pattern == "dots-50" && s2.fill.bg_color == ColorRef.swatch ("Yellow"));
    var w2 = q.pages[0].items[1] as WordArtItem;
    assert (w2 != null && w2.text == "Hello" && w2.warp == WarpKind.ARCH_UP && Math.fabs (w2.warp_amount - 0.7) < 0.001);
    var i2 = (ImageFrame) q.pages[1].items[0];
    assert (Math.fabs (i2.brightness - 0.25) < 0.001 && Math.fabs (i2.contrast + 0.5) < 0.001 && i2.recolor == 2 && i2.clip_shape == "heart" && i2.alt_decorative);
    var t2 = (TextFrame) q.pages[0].items[2];
    assert (t2.autofit == 1 && t2.vertical);
    var r2 = q.story (t2.story).paras[0].runs[0];
    assert (r2.fmt.link == "bookmark:Intro" && r2.fmt.outline_width == 0.8 && r2.fmt.text_shadow == 1 && r2.fmt.emboss == 2);
    assert (q.bookmarks.size == 1 && q.bookmarks[0].name == "Intro" && q.bookmarks[0].page == 1);
    assert (q.business.get ("name") == "Ada Lovelace" && q.color_scheme == "Aqua" && q.font_scheme == "Modern");
    assert (q.macros.size == 1 && q.macros[0].script.contains ("replace"));
    assert (q.merge.filters.size == 1 && q.merge.filters[0].op == FilterOp.CONTAINS && q.merge.sorts[0].descending && q.merge.excluded.contains (0) && q.merge.email_field == "Name");
    assert (q.settings.icc_profile == "/nowhere.icc" && q.settings.intent == 0 && !q.settings.overprint_black);
    var c = p.clone ();
    assert (((ShapeItem) c.pages[0].items[0]).effects.glow);
    assert (c.bookmarks.size == 1 && c.macros.size == 1 && c.merge.filters.size == 1);
}

void test_autofit () {
    var p = base_pub ();
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 200, 80);
    fill (p, t, 6, 40);
    var cache = new LayoutCache (p);
    assert (cache.story (t.story).overset);
    t.autofit = 1;
    cache.invalidate ();
    var r = cache.story (t.story);
    assert (!r.overset);
    assert (r.scale < 0.9 && r.scale > 0.05);
    var t2 = p.add_text_frame (p.pages[0].items, 20, 150, 250, 120);
    var st = p.story (t2.story);
    st.insert_text (TextPos (0, 0), "Big");
    t2.autofit = 2;
    var r2 = cache.story (t2.story);
    assert (!r2.overset);
    assert (r2.scale > 2);
    t2.autofit = 1;
    cache.invalidate ();
    assert (cache.story (t2.story).scale == 1);
}

void test_autoflow () {
    var p = base_pub ();
    var m = p.margin_rect (0);
    var t = p.add_text_frame (p.pages[0].items, m.x, m.y, m.w, m.h);
    fill (p, t, 30, 60);
    int added = Autoflow.run (p, t.story);
    assert (added >= 2);
    assert (p.pages.size == 1 + added);
    var engine = new TextEngine (p);
    assert (!engine.layout_story (t.story).overset);
    assert (p.thread_frames (t.story).size == 1 + added);
}

void test_wrap_through () {
    var o = new Obstacle ();
    o.offset = 0;
    o.mode = WrapMode.THROUGH;
    foreach (var pt in new Point[] { Point (0, 0), Point (30, 0), Point (30, 100), Point (70, 100), Point (70, 0), Point (100, 0), Point (100, 120), Point (0, 120) }) o.poly.add (pt);
    var cuts = o.intervals (20, 30);
    assert (cuts.size == 2);
    assert (cuts[0].a <= 0.1 && Math.fabs (cuts[0].b - 30) < 0.1);
    assert (Math.fabs (cuts[1].a - 70) < 0.1);
    var bottom = o.intervals (105, 110);
    assert (bottom.size == 1 && bottom[0].b >= 99.9);
    var p = base_pub ();
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 260, 260);
    fill (p, t, 8, 50);
    var u = new ShapeItem (ShapeKind.PATH);
    u.id = p.next_id ();
    u.x = 20;
    u.y = 20;
    u.w = 260;
    u.h = 150;
    u.layer = p.layers[0].id;
    foreach (var pt in new Point[] { Point (0, 0), Point (0.2, 0), Point (0.2, 0.9), Point (0.8, 0.9), Point (0.8, 0), Point (1, 0), Point (1, 1), Point (0, 1) }) u.points.add (pt);
    u.wrap = WrapMode.THROUGH;
    u.wrap_offset = 2;
    p.pages[0].items.add (u);
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    int inside = 0;
    foreach (var l in fr.lines) if (l.baseline < 120 && l.x > 45 && l.x < 200) inside++;
    assert (inside > 0);
    u.wrap = WrapMode.CONTOUR;
    cache.invalidate ();
    fr = cache.story (t.story).frames[0];
    int inside2 = 0;
    foreach (var l in fr.lines) if (l.baseline < 120 && l.x > 45 && l.x < 200) inside2++;
    assert (inside2 == 0);
    u.wrap = WrapMode.BEHIND;
    cache.invalidate ();
    fr = cache.story (t.story).frames[0];
    assert (fr.lines[0].x < 10);
    var r = new Renderer (p);
    var order = r.ordered (p.pages[0].items);
    assert (order[0] == u);
    u.wrap = WrapMode.IN_FRONT;
    order = r.ordered (p.pages[0].items);
    assert (order[order.size - 1] == u);
}

void test_wrap_points () {
    var p = base_pub ();
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 260, 260);
    fill (p, t, 8, 50);
    var s = rect (p, 20, 20, 120, 120, ColorRef.swatch ("Cyan"));
    s.wrap = WrapMode.CONTOUR;
    s.wrap_offset = 0;
    p.pages[0].items.add (s);
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    double x_full = fr.lines[1].x;
    assert (x_full > 115);
    s.wrap_points.add (Point (0, 0));
    s.wrap_points.add (Point (0.25, 0));
    s.wrap_points.add (Point (0.25, 1));
    s.wrap_points.add (Point (0, 1));
    cache.invalidate ();
    fr = cache.story (t.story).frames[0];
    assert (fr.lines[1].x < 60);
}

void test_vertical () {
    var p = base_pub ();
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 60, 250);
    fill (p, t, 1, 12);
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    int horiz = fr.lines.size;
    t.vertical = true;
    cache.invalidate ();
    fr = cache.story (t.story).frames[0];
    assert (fr.lines.size < horiz);
    foreach (var l in fr.lines) assert (l.x + l.width <= 250 + 1);
    var s = render (p);
    assert (count_non_white (s, 20, 20, 80, 270) > 50);
}

void test_fills_and_effects () {
    var p = base_pub ();
    var pat = rect (p, 10, 10, 80, 80, ColorRef.swatch ("Black"));
    pat.fill.kind = FillKind.PATTERN;
    pat.fill.pattern = "checker-large";
    pat.fill.bg_color = ColorRef.PAPER;
    p.pages[0].items.add (pat);
    var tex = rect (p, 110, 10, 80, 80, "");
    tex.fill.kind = FillKind.TEXTURE;
    tex.fill.texture = "wood";
    p.pages[0].items.add (tex);
    var s = render (p);
    int dark = 0, light = 0;
    for (int y = 12; y < 88; y += 2) for (int x = 12; x < 88; x += 2) {
        var c = px (s, x, y);
        if (c[0] < 60) dark++;
        else if (c[0] > 200) light++;
    }
    assert (dark > 50 && light > 50);
    var a = px (s, 120, 20);
    var b = px (s, 170, 70);
    assert (!white (a) && a[0] > a[2]);
    bool varies = false;
    for (int x = 115; x < 185; x++) {
        var c = px (s, x, 50);
        if (Math.fabs (c[0] - a[0]) > 12) varies = true;
    }
    assert (varies);
    assert (!white (b));
    var q = base_pub ();
    var g = rect (q, 100, 100, 60, 60, "#2050ff");
    g.effects.glow = true;
    g.effects.glow_size = 10;
    g.effects.glow_color = "#ff0000";
    g.effects.glow_opacity = 1;
    q.pages[0].items.add (g);
    s = render (q);
    var halo = px (s, 95, 130);
    assert (halo[0] > halo[2] && !white (halo));
    assert (white (px (s, 70, 130)));
    var r = base_pub ();
    var refl = rect (r, 100, 40, 60, 60, "#000000");
    refl.effects.reflection = true;
    refl.effects.reflection_size = 0.5;
    refl.effects.reflection_opacity = 0.8;
    r.pages[0].items.add (refl);
    s = render (r);
    assert (!white (px (s, 130, 110)));
    assert (white (px (s, 130, 170)));
    var e = base_pub ();
    var soft = rect (e, 100, 100, 80, 80, "#000000");
    soft.effects.soft_edges = 20;
    e.pages[0].items.add (soft);
    s = render (e);
    var edge = px (s, 101, 140);
    var mid = px (s, 140, 140);
    assert (mid[0] < 30);
    assert (edge[0] > mid[0] + 60);
    var bv = base_pub ();
    var bev = rect (bv, 100, 100, 80, 80, "#808080");
    bev.effects.bevel = true;
    bev.effects.bevel_depth = 8;
    bv.pages[0].items.add (bev);
    s = render (bv);
    assert (px (s, 103, 103)[0] > px (s, 176, 176)[0] + 30);
}

void test_wordart_and_border () {
    var p = base_pub ();
    var wa = new WordArtItem ();
    wa.id = p.next_id ();
    wa.layer = p.layers[0].id;
    wa.text = "WORDART";
    wa.font = "DejaVu Sans";
    wa.x = 20;
    wa.y = 20;
    wa.w = 260;
    wa.h = 80;
    wa.fill = new Fill.solid ("#ff0000");
    p.pages[0].items.add (wa);
    var s = render (p);
    int plain = count_non_white (s, 20, 20, 280, 100);
    assert (plain > 2000);
    assert (count_non_white (s, 0, 110, 300, 300) == 0);
    wa.warp = WarpKind.ARCH_UP;
    wa.warp_amount = 1;
    s = render (p);
    assert (count_non_white (s, 20, 20, 280, 100) > 500);
    int top_mid = count_non_white (s, 120, 20, 180, 45);
    int top_side = count_non_white (s, 20, 20, 60, 45);
    assert (top_mid > top_side);
    assert (count_non_white (s, 0, 102, 300, 300) == 0);
    assert (count_non_white (s, 282, 0, 300, 300) == 0);
    var q = base_pub ();
    var b = rect (q, 40, 40, 200, 200, ColorRef.NONE);
    b.fill = new Fill ();
    b.border_art.design = "stars";
    b.border_art.size = 20;
    b.border_art.color = "#0000ff";
    q.pages[0].items.add (b);
    s = render (q);
    assert (count_non_white (s, 40, 40, 240, 60) > 200);
    assert (count_non_white (s, 70, 70, 210, 210) == 0);
    foreach (string id in FxRender.border_ids ()) {
        b.border_art.design = id;
        s = render (q);
        assert (count_non_white (s, 40, 40, 240, 240) > 50);
    }
}

void test_text_effects_and_links () {
    var p = base_pub ();
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 260, 100);
    var st = p.story (t.story);
    st.insert_text (TextPos (0, 0), "OUTLINE");
    st.apply_chars (TextPos (0, 0), st.end_pos (), (r) => {
        r.fmt.size = 48;
        r.fmt.color = ColorRef.PAPER;
        r.fmt.outline_color = "#ff0000";
        r.fmt.outline_width = 2;
        r.fmt.font = "DejaVu Sans";
    });
    var s = render (p);
    int red = 0;
    for (int y = 20; y < 120; y++) for (int x = 20; x < 280; x++) {
        var c = px (s, x, y);
        if (c[0] > 200 && c[1] < 80 && c[2] < 80) red++;
    }
    assert (red > 100);
    st.apply_chars (TextPos (0, 0), st.end_pos (), (r) => {
        r.fmt.outline_color = "";
        r.fmt.color = ColorRef.BLACK;
        r.fmt.text_shadow = 1;
        r.fmt.glow_color = "#00ff00";
        r.fmt.glow_size = 6;
        r.fmt.reflection = 1;
    });
    s = render (p);
    int green = 0;
    for (int y = 10; y < 130; y++) for (int x = 10; x < 290; x++) {
        var c = px (s, x, y);
        if (c[1] > c[0] + 40 && c[1] > c[2] + 40) green++;
    }
    assert (green > 100);
    st.apply_chars (TextPos (0, 0), TextPos (0, 3), (r) => r.fmt.link = "https://example.org/");
    p.bookmarks.add (new Bookmark ("Top Of Page", 0, 0, 0));
    var t2 = p.add_text_frame (p.pages[0].items, 20, 200, 200, 40);
    p.story (t2.story).insert_text (TextPos (0, 0), "Back");
    p.story (t2.story).apply_chars (TextPos (0, 0), TextPos (0, 4), (r) => r.fmt.link = "bookmark:Top Of Page");
    var box = rect (p, 240, 200, 40, 40, "#000000");
    box.link = "mailto:someone@example.org";
    p.pages[0].items.add (box);
    string path = Path.build_filename (outdir (), "links.pdf");
    try {
        new Exporter (p, new ExportOptions ()).export_pdf (path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var f = PdfFile.parse (data);
        var page = f.pages ()[0];
        var annots = f.deref (page.get ("Annots"));
        assert (annots != null && annots.items.size >= 3);
        int uris = 0, gotos = 0;
        foreach (var a in annots.items) {
            var ad = f.deref (a);
            if (ad.get ("A") == null) {
                if (ad.get ("Dest") != null) gotos++;
                continue;
            }
            var act = f.deref (ad.get ("A"));
            string sname = act.name_of ("S");
            if (sname == "URI") uris++;
            else if (sname == "GoTo") gotos++;
        }
        assert (uris >= 2 && gotos >= 1);
        var root = f.deref (f.trailer.get ("Root"));
        assert (root.get ("Outlines") != null);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
}

void test_image_corrections () {
    var p = base_pub ();
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 40, 40);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 0.2, 0.1);
    cr.paint ();
    string path = Path.build_filename (outdir (), "red.png");
    surf.write_to_png (path);
    uint8[] data;
    try {
        FileUtils.get_data (path, out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.layer = p.layers[0].id;
    im.x = 50;
    im.y = 50;
    im.w = 100;
    im.h = 100;
    im.media = p.add_media (data, "red.png");
    p.pages[0].items.add (im);
    var s = render (p);
    var c0 = px (s, 100, 100);
    assert (c0[0] > 200 && c0[1] < 100);
    im.recolor = 1;
    s = render (p);
    var c1 = px (s, 100, 100);
    assert (Math.fabs (c1[0] - c1[1]) < 4 && Math.fabs (c1[1] - c1[2]) < 4);
    im.recolor = 0;
    im.brightness = 0.6;
    s = render (p);
    assert (px (s, 100, 100)[1] > c0[1] + 60);
    im.brightness = 0;
    im.transparent_color = "#ff3319";
    s = render (p);
    assert (white (px (s, 100, 100)));
    im.transparent_color = "";
    im.clip_shape = "ellipse";
    s = render (p);
    assert (white (px (s, 52, 52)));
    assert (!white (px (s, 100, 100)));
    var other = (ImageFrame) im.clone ();
    other.id = p.next_id ();
    other.media = "";
    PictureStyles.swap (im, other);
    assert (im.media == "" && other.media != "");
    PictureStyles.apply (other, "simple-white");
    assert (other.stroke.visible () && other.shadow.enabled);
    PictureStyles.apply (other, "oval");
    assert (other.clip_shape == "ellipse" && !other.stroke.visible ());
    var g = Captions.add (p, p.pages[0].items, other, "below", "A caption");
    assert (g.children.size == 2 && g.children[0] == other && g.children[1] is TextFrame);
    assert (p.story (((TextFrame) g.children[1]).story).plain_text () == "A caption");
    assert (p.pages[0].items.contains (g) && !p.pages[0].items.contains (other));
}

void test_schemes_and_blocks () {
    var p = base_pub ();
    var cs = ColorScheme.find ("Aqua");
    assert (cs != null);
    cs.apply (p);
    var main_sw = p.swatch ("Main");
    assert (main_sw != null && main_sw.rgba ().to_hex () != "#000000");
    var accent = p.swatch ("Accent 1");
    Rgba want;
    Rgba.parse_hex (cs.colors[1], out want);
    var got = accent.rgba ();
    assert (Math.fabs (got.r - want.r) < 0.15 && Math.fabs (got.g - want.g) < 0.15 && Math.fabs (got.b - want.b) < 0.15);
    assert (ColorScheme.builtins ().size >= 40);
    var fs = FontScheme.find ("Archival");
    fs.apply (p);
    assert (p.styles.find_paragraph ("Heading 1").chars.font == fs.heading_font ());
    assert (p.styles.find_paragraph (StyleSheet.BASIC).chars.font == fs.body_font ());
    int built = 0;
    var overset = new Gee.ArrayList<string> ();
    foreach (var b in BuildingBlocks.builtins ()) {
        var g = BuildingBlocks.build (p, b.id, 10, 10);
        assert (g != null && g.children.size > 0);
        assert (Math.fabs (g.x - 10) < 0.01 && Math.fabs (g.y - 10) < 0.01);
        p.pages[0].items.add (g);
        var lc = new LayoutCache (p);
        foreach (var ch in g.children) {
            var tf = ch as TextFrame;
            if (tf == null) continue;
            if (lc.story (tf.story).overset) overset.add (b.id);
        }
        p.pages[0].items.remove (g);
        built++;
    }
    assert (built >= 30);
    if (overset.size > 0) error ("building blocks with overset text: %s", string.joinv (", ", overset.to_array ()));
    BuildingBlocks.calendar_year = 2026;
    BuildingBlocks.calendar_month = 2;
    var cal = BuildingBlocks.build (p, "calendar-grid", 0, 0);
    TableItem? tb = null;
    foreach (var c in cal.children) if (c is TableItem) tb = (TableItem) c;
    assert (tb != null && tb.cols == 7);
    int days = 0;
    for (int r = 1; r < tb.rows; r++) foreach (var cell in tb.cells[r]) if (!cell.story.is_empty ()) days++;
    assert (days == 28);
    p.business.set ("organization", "Northwind");
    var biz = BuildingBlocks.build (p, "biz-contact", 0, 0);
    p.pages[0].items.add (biz);
    var fc = new FieldContext (p);
    assert (fc.resolve (Fields.biz ("organization")) == "Northwind");
    string dir = outdir ();
    Environment.set_variable ("XDG_DATA_HOME", dir, true);
    try {
        var items = new Gee.ArrayList<Item> ();
        items.add (biz);
        string id = BuildingBlocks.save_user (p, items, "Mine");
        bool listed = false;
        foreach (var b in BuildingBlocks.user_blocks ()) if (b.id == id && b.name == "Mine") listed = true;
        assert (listed);
        var back = BuildingBlocks.build (p, id, 50, 60);
        assert (back != null && Math.fabs (back.x - 50) < 0.01);
        bool found_field = false;
        p.pages[0].items.add (back);
        foreach (var r in p.all_items ()) {
            var t = r.item as TextFrame;
            if (t != null && p.story (t.story).fields ().contains (Fields.biz ("organization"))) found_field = true;
        }
        assert (found_field);
        BuildingBlocks.delete_user (id);
        assert (BuildingBlocks.user_blocks ().size == 0);
        var info = new BusinessInfo ();
        info.set_name = "Home";
        info.set ("email", "me@example.org");
        BusinessSets.save (info);
        assert (BusinessSets.find ("Home").get ("email") == "me@example.org");
        var custom = new ColorScheme ("Mine", cs.colors);
        ColorScheme.save_custom (custom);
        assert (ColorScheme.find ("Mine") != null && ColorScheme.find ("Mine").custom);
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
    var t = new TableItem (4, 3);
    t.id = p.next_id ();
    t.w = 150;
    t.h = 80;
    t.init_cells (p);
    t.cells[0][0].story.insert_text (TextPos (0, 0), "Head");
    TableFormats.apply (p, t, "medium-1");
    assert (t.header_fill == ColorScheme.slot_spec (1) && t.alt_fill != ColorRef.NONE);
    assert (t.cells[0][0].story.paras[0].runs[0].fmt.color == ColorRef.PAPER);
    foreach (string id in TableFormats.ids ()) TableFormats.apply (p, t, id);
    foreach (var sp in ShapeLib.all ()) assert (ShapeLib.points (sp.id).size >= 3);
}

void test_accessibility () {
    var p = base_pub ();
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.media = p.add_media ({ 1, 2, 3 }, "x.png");
    p.pages[0].items.add (im);
    var t = p.add_text_frame (p.pages[0].items, 10, 10, 200, 40);
    p.story (t.story).insert_text (TextPos (0, 0), "faint text");
    p.story (t.story).apply_chars (TextPos (0, 0), p.story (t.story).end_pos (), (r) => r.fmt.color = "#dddddd");
    var tb = new TableItem (2, 2);
    tb.id = p.next_id ();
    tb.header_rows = 0;
    tb.init_cells (p);
    p.pages[0].items.add (tb);
    var pf = new Preflight (p);
    pf.check_accessibility = true;
    pf.check_print = false;
    pf.check_general = false;
    pf.run ();
    bool alt = false, contrast = false, title = false, header = false;
    foreach (var i in pf.issues) {
        if (i.kind == IssueKind.ALT_TEXT) alt = true;
        if (i.kind == IssueKind.CONTRAST) contrast = true;
        if (i.kind == IssueKind.NO_TITLE) title = true;
        if (i.kind == IssueKind.TABLE_HEADER) header = true;
        assert (i.category () == "Accessibility");
    }
    assert (alt && contrast && title && header);
    im.alt_decorative = true;
    p.meta.title = "Flyer";
    p.story (t.story).apply_chars (TextPos (0, 0), p.story (t.story).end_pos (), (r) => r.fmt.color = ColorRef.BLACK);
    tb.header_rows = 1;
    foreach (var row in tb.cells) foreach (var c in row) c.story.insert_text (TextPos (0, 0), "x");
    pf.run ();
    assert (pf.count (Severity.WARNING) == 0 && pf.count (Severity.ERROR) == 0);
    assert (AccessibilityChecker.contrast (Rgba (0, 0, 0, 1), Rgba (1, 1, 1, 1)) > 20);
    assert (AccessibilityChecker.vague_link ("click here"));
}

void test_merge_selection () {
    var p = base_pub ();
    var t = new DataTable ();
    t.fields.add ("Name");
    t.fields.add ("City");
    t.fields.add ("Age");
    string[,] rows = { { "Ann", "Rome", "31" }, { "Bob", "Milan", "9" }, { "Cid", "Rome", "45" }, { "Dan", "Turin", "22" } };
    for (int i = 0; i < 4; i++) t.records.add (new Gee.ArrayList<string>.wrap ({ rows[i, 0], rows[i, 1], rows[i, 2] }));
    Merge.set_source (p, t, "csv", "");
    var f = p.add_text_frame (p.pages[0].items, 10, 10, 200, 40);
    p.story (f.story).insert_field (TextPos (0, 0), Fields.merge ("Name"));
    p.merge.filters.add (new MergeFilter ("City", FilterOp.EQUALS, "rome"));
    var sel = p.merge.selected_records ();
    assert (sel.size == 2 && sel[0] == 0 && sel[1] == 2);
    p.merge.filters.add (new MergeFilter ("Age", FilterOp.LESS, "25", true));
    sel = p.merge.selected_records ();
    assert (sel.size == 4);
    p.merge.filters.clear ();
    p.merge.sorts.add (new MergeSort ("Age", true));
    sel = p.merge.selected_records ();
    assert (sel[0] == 2 && sel[3] == 1);
    p.merge.excluded.add (2);
    sel = p.merge.selected_records ();
    assert (sel.size == 3 && sel[0] == 0);
    var out_pub = Merge.expand (p);
    assert (out_pub.pages.size == 3);
    var first = (TextFrame) out_pub.pages[0].items[0];
    assert (out_pub.story (first.story).plain_text () == "Ann");
}

class FakeHost : MacroHost {
    public Publication pub;
    public int page = 0;
    public Gee.ArrayList<string> actions = new Gee.ArrayList<string> ();
    public StringBuilder typed = new StringBuilder ();
    public Gee.ArrayList<string> messages = new Gee.ArrayList<string> ();

    public override Publication publication () {
        return pub;
    }

    public override bool run_action (string name, string? param) {
        if (name == "missing") return false;
        actions.add (param != null ? name + ":" + param : name);
        if (name == "add-page") pub.add_page (-1, "A");
        return true;
    }

    public override void insert_text (string text) {
        typed.append (text);
    }

    public override void go_to_page (int index) {
        page = index;
    }

    public override void select_items (Gee.List<Item> items) {
        actions.add ("select:%d".printf (items.size));
    }

    public override Gee.List<Item> page_items (int index) {
        return pub.pages[index].items;
    }

    public override void format_chars (string key, string value) {
        actions.add ("fmt:%s=%s".printf (key, value));
    }

    public override void apply_style (string name) {
        actions.add ("style:" + name);
    }

    public override void export_pdf (string path) throws Error {
        new Exporter (pub, new ExportOptions ()).export_pdf (path);
    }

    public override void changed () {
    }

    public override void message (string text) {
        messages.add (text);
    }
}

void test_macros () {
    var p = base_pub (3);
    var t = p.add_text_frame (p.pages[0].items, 10, 10, 100, 40);
    p.story (t.story).insert_text (TextPos (0, 0), "colour colour");
    p.add_text_frame (p.pages[1].items, 10, 10, 100, 40);
    var host = new FakeHost ();
    host.pub = p;
    var engine = new MacroEngine ();
    try {
        string script = "# tidy up\nreplace \"colour\" \"color\"\nrepeat 2\n  type \"ab\"\nend\nfor-each-page\n  action bold\nend\nfor-each-text-frame\n  size 14\nend\nstyle \"Body Text\"\nnew-page\nmessage done here\n";
        engine.run (host, script);
        assert (p.story (t.story).plain_text () == "color color");
        assert (host.typed.str == "abab");
        int bolds = 0, selects = 0, sizes = 0;
        foreach (string a in host.actions) {
            if (a == "bold") bolds++;
            if (a.has_prefix ("select:")) selects++;
            if (a == "fmt:size=14") sizes++;
        }
        assert (bolds == 3 && selects == 2 && sizes == 2);
        assert (host.actions.contains ("style:Body Text") && p.pages.size == 4);
        assert (host.messages.size == 1 && host.messages[0] == "done here");
    } catch (Error e) {
        warning ("%s", e.message);
        assert_not_reached ();
    }
    bool failed = false;
    try {
        MacroEngine.parse ("repeat 2\ntype x\n");
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    failed = false;
    try {
        MacroEngine.parse ("launch rockets\n");
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    failed = false;
    try {
        engine.run (host, "action missing\n");
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
}

void test_thesaurus () {
    string dir = outdir ();
    string dat = "UTF-8\nhappy|2\n(adj)|glad|cheerful|content\n(adj)|lucky|fortunate\nsad|1\n(adj)|unhappy|blue\n";
    int happy_off = "UTF-8\n".length;
    int sad_off = dat.index_of ("sad|");
    string idx = "UTF-8\n2\nhappy|%d\nsad|%d\n".printf (happy_off, sad_off);
    try {
        FileUtils.set_contents (Path.build_filename (dir, "th_en_US_v2.dat"), dat);
        FileUtils.set_contents (Path.build_filename (dir, "th_en_US_v2.idx"), idx);
    } catch (Error e) {
        assert_not_reached ();
    }
    Environment.set_variable ("PUBLISH_THESAURUS_PATH", dir, true);
    assert (Thesaurus.languages ().contains ("en_US"));
    var th = Thesaurus.for_language ("en_US");
    assert (th != null);
    var res = th.lookup ("Happy");
    assert (res.size == 2 && res[0].part == "adj" && res[0].words.contains ("cheerful") && res[1].words.contains ("fortunate"));
    assert (th.lookup ("sad")[0].words[0] == "unhappy");
    assert (th.lookup ("nothing").size == 0);
}

void test_tiling () {
    var p = base_pub ();
    p.settings.width = 595;
    p.settings.height = 842;
    var o = new ExportOptions ();
    o.impose = ImposeMode.TILE;
    o.tile_scale = 2;
    o.tile_overlap = 18;
    o.bleed = false;
    o.sheet_w = 595;
    o.sheet_h = 842;
    var ex = new Exporter (p, o);
    var sheets = ex.sheets ();
    assert (sheets.size == 9);
    foreach (var sh in sheets) {
        assert (sh.tile.w > 0 && sh.tile.h > 0);
        assert (sh.tile.x >= 17.9 && sh.tile.x + sh.tile.w <= 595 - 17.9);
    }
    assert (sheets[0].slots[0].row == 0 && sheets[8].slots[0].row == 2 && sheets[8].slots[0].col == 2);
    string path = Path.build_filename (outdir (), "tiles.pdf");
    try {
        assert (ex.export_pdf (path) == 9);
    } catch (Error e) {
        assert_not_reached ();
    }
    o.tile_scale = 0.5;
    assert (new Exporter (p, o).sheets ().size == 1);
}

uint8[] fake_font (uint16 fs_type) {
    var b = new ByteArray ();
    b.append ({ 0, 1, 0, 0, 0, 1, 0, 16, 0, 0, 0, 0 });
    b.append ("OS/2".data);
    b.append ({ 0, 0, 0, 0, 0, 0, 0, 28, 0, 0, 0, 10 });
    b.append ({ 0, 3, 1, 244, 0, 5, 0, 0, (uint8) (fs_type >> 8), (uint8) (fs_type & 0xFF) });
    return b.steal ();
}

void test_font_package () {
    assert (FontPackager.licence_of (fake_font (0)) == FontLicence.INSTALLABLE);
    assert (FontPackager.licence_of (fake_font (2)) == FontLicence.RESTRICTED);
    assert (FontPackager.licence_of (fake_font (4)) == FontLicence.PRINT_PREVIEW);
    assert (FontPackager.licence_of (fake_font (8)) == FontLicence.EDITABLE);
    assert (FontPackager.licence_of (new uint8[40]) == FontLicence.UNKNOWN);
    assert (!FontLicence.RESTRICTED.may_copy ());
    assert (FontLicence.INSTALLABLE.may_copy ());
    string dir;
    try {
        dir = DirUtils.make_tmp ("fontpkg-XXXXXX");
    } catch (Error e) {
        error (e.message);
    }
    var none = new Gee.ArrayList<string> ();
    none.add ("No Such Family Qwxz");
    assert (FontPackager.collect (none, dir).size == 0);
    var fm = Pango.CairoFontMap.get_default ();
    Pango.FontFamily[] fams;
    fm.list_families (out fams);
    string? family = null;
    foreach (var f in fams) {
        if (FontPackager.files_for (f.get_name ()).size > 0) {
            family = f.get_name ();
            break;
        }
    }
    if (family == null) {
        DirUtils.remove (dir);
        return;
    }
    var want = new Gee.ArrayList<string> ();
    want.add (family);
    var got = FontPackager.collect (want, dir);
    assert (got.size > 0);
    foreach (var pf in got) {
        string dst = Path.build_filename (dir, Path.get_basename (pf.file));
        assert (pf.copied == pf.licence.may_copy ());
        assert (FileUtils.test (dst, FileTest.EXISTS) == pf.copied);
        if (pf.copied) FileUtils.unlink (dst);
    }
    DirUtils.remove (dir);
}

void test_picture_placement () {
    var p = Publication.create (new DocSettings (), 1);
    var items = p.pages[0].items;
    var a = new ImageFrame ();
    a.x = 300; a.y = 100; a.w = 100; a.h = 100;
    var b = new ImageFrame ();
    b.x = 50; b.y = 102; b.w = 100; b.h = 100;
    var full = new ImageFrame ();
    full.x = 50; full.y = 20; full.w = 100; full.h = 50;
    full.media = "m1";
    var c = new ImageFrame ();
    c.x = 50; c.y = 400; c.w = 100; c.h = 100;
    items.add (a);
    items.add (b);
    items.add (full);
    items.add (c);
    var e = PicturePlacement.empty_frames (items);
    assert (e.size == 3);
    assert (e[0] == b && e[1] == a && e[2] == c);
    var s0 = PicturePlacement.scratch_slot (p, items, 0);
    assert (s0.x > p.settings.width);
    var extra = new ImageFrame ();
    extra.x = s0.x; extra.y = s0.y; extra.w = s0.w; extra.h = s0.h;
    items.add (extra);
    var s1 = PicturePlacement.scratch_slot (p, items, 0);
    assert (s1.x != s0.x || s1.y != s0.y);
    var r0 = Rect (s0.x, s0.y, s0.w, s0.h);
    var r1 = Rect (s1.x, s1.y, s1.w, s1.h);
    assert (!r0.intersects (r1));
}

void test_macro_language () {
    var p = base_pub (2);
    var a = p.add_text_frame (p.pages[0].items, 10, 10, 200, 60);
    p.story (a.story).paras.clear ();
    p.story (a.story).paras.add (new Paragraph.with_text ("Summer sale"));
    p.story (a.story).paras.add (new Paragraph.with_text ("All week"));
    a.name = "Title";
    var b = p.add_text_frame (p.pages[1].items, 10, 10, 200, 60);
    p.story (b.story).paras.clear ();
    p.story (b.story).paras.add (new Paragraph.with_text ("Footer"));
    var host = new FakeHost ();
    host.pub = p;
    var engine = new MacroEngine ();
    string script = """
set total = 0
set words = ""
for-each-item text
  set total = total + 1
  if item.name == "Title"
    set-item x 50
    set-item fill "#ff0000"
  elif item.y > 5
    set-item name "Other"
  else
    message "never"
  end
end
define-style "Big Head" font "DejaVu Sans" size 30 bold on align center space-after 6
for-each-item text
  for-each-paragraph
    if paragraph.number == 1 and contains(paragraph.text, "sale")
      set-paragraph style "Big Head"
    end
    set words = words + upper(paragraph.text) + ";"
  end
end
set n = 0
while n < 100
  set n = n + 7
  if n > 20
    break
  end
end
for i from 1 to 3
  add-shape ellipse {i * 10} 400 20 20 "#00ff00"
end
page 2
add-text-frame 30 30 100 40 "Made on page {page.number} of {pages.count}"
message "{total} frames, n={n}, shapes={count('shape')}"
""";
    try {
        engine.run (host, script);
    } catch (Error e) {
        error (e.message);
    }
    assert (engine.vars["total"].to_num () == 2);
    assert (a.x == 50 && a.fill.color == "#ff0000");
    assert (b.name == "Other");
    var bh = p.styles.find_paragraph ("Big Head");
    assert (bh != null && bh.chars.size == 30 && bh.chars.bold == 1 && bh.para.align == (int) TextAlign.CENTER);
    assert (p.story (a.story).paras[0].style == "Big Head");
    assert (p.story (a.story).paras[1].style != "Big Head");
    assert (engine.vars["words"].to_string () == "SUMMER SALE;ALL WEEK;FOOTER;");
    assert (engine.vars["n"].to_num () == 21);
    int shapes = 0;
    foreach (var it in p.pages[0].items) if (it is ShapeItem) shapes++;
    assert (shapes == 3);
    bool made = false;
    foreach (var it in p.pages[1].items) {
        var t = it as TextFrame;
        if (t != null && p.story (t.story).plain_text () == "Made on page 2 of 2") made = true;
    }
    assert (made);
    assert (host.messages[host.messages.size - 1] == "2 frames, n=21, shapes=3");
    bool failed = false;
    try {
        MacroEngine.parse ("else\n");
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    failed = false;
    try {
        engine.run (host, "set x = 1 / 0\n");
    } catch (Error e) {
        failed = e.message.contains ("zero");
    }
    assert (failed);
    failed = false;
    try {
        engine.run (host, "message {nosuch}\n");
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    var m = new MacroDef ("Stamp", "message hi\n");
    m.event = "open";
    p.macros.add (m);
    assert (MacroEngine.for_event (p, "open") == m);
    assert (MacroEngine.for_event (p, "save") == null);
    try {
        var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
        assert (MacroEngine.for_event (q, "open") != null && MacroEngine.for_event (q, "open").name == "Stamp");
    } catch (Error e) {
        error (e.message);
    }
}

void main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/features/roundtrip", test_roundtrip_new_fields);
    Test.add_func ("/features/autofit", test_autofit);
    Test.add_func ("/features/autoflow", test_autoflow);
    Test.add_func ("/features/wrap-through", test_wrap_through);
    Test.add_func ("/features/wrap-points", test_wrap_points);
    Test.add_func ("/features/vertical", test_vertical);
    Test.add_func ("/features/fills-effects", test_fills_and_effects);
    Test.add_func ("/features/wordart-border", test_wordart_and_border);
    Test.add_func ("/features/text-effects-links", test_text_effects_and_links);
    Test.add_func ("/features/image-corrections", test_image_corrections);
    Test.add_func ("/features/schemes-blocks", test_schemes_and_blocks);
    Test.add_func ("/features/accessibility", test_accessibility);
    Test.add_func ("/features/merge-selection", test_merge_selection);
    Test.add_func ("/features/macros", test_macros);
    Test.add_func ("/features/macro-language", test_macro_language);
    Test.add_func ("/features/thesaurus", test_thesaurus);
    Test.add_func ("/features/tiling", test_tiling);
    Test.add_func ("/features/font-package", test_font_package);
    Test.add_func ("/features/picture-placement", test_picture_placement);
    Test.run ();
}
