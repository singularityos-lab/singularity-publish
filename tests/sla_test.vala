using Singularity.Apps.Publish;

string fixtures_dir () {
    string? root = Environment.get_variable ("PUBLISH_FIXTURES");
    if (root == null || root == "") root = "fixtures";
    return Path.build_filename (root, "sla");
}

bool near (double a, double b, double eps = 0.01) {
    return Math.fabs (a - b) <= eps;
}

Publication read_fixture (string name, out SlaReader reader) {
    reader = new SlaReader ();
    reader.base_dir = fixtures_dir ();
    uint8[] data;
    try {
        FileUtils.get_data (Path.build_filename (fixtures_dir (), name), out data);
        return reader.read (data);
    } catch (Error e) {
        error ("could not read %s: %s", name, e.message);
    }
}

Publication round_trip (Publication p, out SlaReader reader) {
    reader = new SlaReader ();
    reader.base_dir = p.base_dir;
    try {
        string xml = new SlaWriter (p).write ();
        return reader.read (xml.data);
    } catch (Error e) {
        error ("round trip failed: %s", e.message);
    }
}

string para_text (Story s, int i) {
    return s.paras[i].text ();
}

void test_fixture_document () {
    SlaReader r;
    var p = read_fixture ("brochure.sla", out r);
    var s = p.settings;
    assert (p.pages.size == 2);
    assert (near (s.width, 595.28) && near (s.height, 841.89));
    assert (near (s.margin_inside, 40) && near (s.margin_outside, 30) && near (s.margin_top, 50) && near (s.margin_bottom, 60));
    assert (near (s.bleed_top, 8.5) && near (s.bleed_inside, 8.5) && near (s.bleed_outside, 8.5) && near (s.bleed_bottom, 8.5));
    assert (!s.facing);
    assert (s.units == "mm");
    assert (s.page_size == "a4");
    assert (s.columns == 2 && near (s.gutter, 12));
    assert (p.meta.title == "Spring Brochure" && p.meta.author == "Test Author" && p.meta.subject == "Offers");
    assert (p.sections.size == 1 && p.sections[0].style == NumberStyle.ROMAN_LOWER && p.sections[0].start_number == 3);
    assert (p.page_label (0) == "iii" && p.page_label (1) == "iv");
    assert (p.pages[0].guides.size == 2 && p.pages[0].guides[0].vertical && near (p.pages[0].guides[1].pos, 200));
    bool found_render = false;
    foreach (string w in r.warnings) if (w.contains ("render frames")) found_render = true;
    assert (found_render);
}

void test_fixture_colors () {
    SlaReader r;
    var p = read_fixture ("brochure.sla", out r);
    var blue = p.swatch ("Brand Blue");
    assert (blue != null && blue.model == ColorModel.CMYK);
    assert (near (blue.c, 1) && near (blue.m, 0.6) && near (blue.y, 0) && near (blue.k, 0.1));
    var spot = p.swatch ("Pantone 185 C");
    assert (spot != null && spot.spot && near (spot.m, 0.9));
    var orange = p.swatch ("Web Orange");
    assert (orange != null && orange.model == ColorModel.RGB && near (orange.r, 1) && near (orange.g, 128 / 255.0));
    assert (p.swatch ("Registration") != null && p.swatch ("Paper") != null && p.swatch ("White") != null);
}

void test_fixture_styles () {
    SlaReader r;
    var p = read_fixture ("brochure.sla", out r);
    var basic = p.styles.find_paragraph (StyleSheet.BASIC);
    assert (basic != null);
    assert (basic.chars.font == "DejaVu Sans" && basic.chars.bold == 0 && near (basic.chars.size, 10));
    assert (near (basic.para.leading, 13));
    var body = p.styles.find_paragraph ("Body");
    assert (body.based_on == StyleSheet.BASIC && body.para.align == (int) TextAlign.JUSTIFY && near (body.para.first_indent, 12));
    var tabs = TabStop.parse (body.para.tabs);
    assert (tabs.size == 1 && tabs[0].kind == TabKind.RIGHT && near (tabs[0].pos, 200) && tabs[0].leader == ".");
    var head = p.styles.find_paragraph ("Heading");
    assert (head.chars.bold == 1 && near (head.chars.size, 24) && near (head.para.space_before, 4) && near (head.para.space_after, 6) && head.para.keep_next == 1);
    var sub = p.styles.find_paragraph ("Subheading");
    assert (sub.based_on == "Heading" && sub.chars.color == "swatch:Brand Blue@80");
    var pf = new ParaFormat ();
    var cf = new CharFormat ();
    p.styles.resolve_paragraph ("Subheading", pf, cf);
    assert (cf.bold == 1 && near (cf.size, 16) && near (pf.leading, 28));
    var intro = p.styles.find_paragraph ("Intro");
    assert (intro.based_on == "Body" && intro.para.drop_lines == 3 && intro.para.drop_chars == 1);
    var pts = p.styles.find_paragraph ("Points");
    assert (pts.para.list_type == 1 && pts.para.bullet == "-" && near (pts.para.left_indent, 14) && near (pts.para.first_indent, -10));
    var accent = p.styles.find_character ("Accent");
    assert (accent != null && accent.chars.underline == 1 && accent.chars.color == "swatch:Brand Blue");
    var loud = p.styles.find_character ("Loud");
    assert (loud.based_on == "Accent" && loud.chars.bold == 1 && loud.chars.font == "DejaVu Sans");
    assert (p.styles.find_character ("Default Character Style") == null);
}

void test_fixture_layers_masters () {
    SlaReader r;
    var p = read_fixture ("brochure.sla", out r);
    assert (p.layers.size == 2);
    assert (p.layers[0].name == "Background" && p.layers[1].name == "Text" && p.layers[1].locked && !p.layers[0].locked);
    assert (p.masters.size == 1 && p.masters[0].name == "Normal" && p.masters[0].id == "A");
    assert (p.pages[0].master == "A" && p.pages[1].master == "A");
    var m = p.masters[0];
    assert (m.items.size == 1 && m.guides.size == 1 && !m.guides[0].vertical);
    var mt = (TextFrame) m.items[0];
    assert (near (mt.x, 500) && near (mt.y, 800));
    var ms = p.stories[mt.story];
    assert (ms.fields ().contains (Fields.PAGE));
    assert (ms.paras[0].fmt.align == (int) TextAlign.RIGHT);
}

void test_fixture_text () {
    SlaReader r;
    var p = read_fixture ("brochure.sla", out r);
    var f1 = (TextFrame) p.pages[0].items[0];
    assert (near (f1.x, 40) && near (f1.y, 50) && near (f1.w, 300) && near (f1.h, 400));
    assert (f1.columns == 2 && near (f1.gutter, 12));
    assert (near (f1.inset_left, 2) && near (f1.inset_top, 3) && near (f1.inset_bottom, 4) && near (f1.inset_right, 5));
    assert (f1.valign == 1);
    assert (f1.layer == p.layers[1].id);
    var st = p.stories[f1.story];
    assert (st.paras.size == 4);
    assert (para_text (st, 0) == "Spring Sale" && st.paras[0].style == "Heading");
    assert (para_text (st, 1) == "Our best offers this week\t12" && st.paras[1].style == "Body");
    bool accent = false;
    foreach (var run in st.paras[1].runs) if (run.cstyle == "Accent" && run.text == "this week") accent = true;
    assert (accent);
    assert (para_text (st, 2) == "Second paragraph with \u2028bold italic and sup");
    assert (st.paras[2].style == "Intro" && st.paras[2].fmt.align == (int) TextAlign.CENTER);
    Run? bi = null;
    Run? sup = null;
    foreach (var run in st.paras[2].runs) {
        if (run.text == "bold italic") bi = run;
        if (run.text == "sup") sup = run;
    }
    assert (bi != null && bi.fmt.font == "DejaVu Sans" && bi.fmt.bold == 1 && bi.fmt.italic == 1 && near (bi.fmt.size, 11) && bi.fmt.color == "swatch:Web Orange");
    assert (sup != null && sup.fmt.position == 1);
    assert (para_text (st, 3) == "First point" && st.paras[3].style == "Points" && st.paras[3].runs[0].cstyle == "Loud");
    var f2 = (TextFrame) p.pages[1].items[0];
    assert (f2.story == f1.story);
    assert (st.frames.size == 2 && st.frames[0] == f1.id && st.frames[1] == f2.id);
    assert (near (f2.x, 40) && near (f2.y, 50));
    var thread = p.thread_frames (st.id);
    assert (thread.size == 2 && thread[1] == f2);
}

void test_fixture_graphics () {
    SlaReader r;
    var p = read_fixture ("brochure.sla", out r);
    var items = p.pages[0].items;
    assert (items.size == 7);
    var im = (ImageFrame) items[1];
    assert (near (im.x, 350) && near (im.y, 60) && near (im.w, 150));
    assert (im.link == File.new_for_path (Path.build_filename (fixtures_dir (), "photo.png")).get_path ());
    assert (im.fit == FitMode.MANUAL && near (im.img_scale, 0.5) && near (im.img_x, 5) && near (im.img_y, 10));
    assert (im.shape_ellipse && im.wrap == WrapMode.CONTOUR);
    assert (ImageStore.status (p, im) == LinkStatus.OK);
    var el = (ShapeItem) items[2];
    assert (el.shape == ShapeKind.ELLIPSE && el.fill.color == "swatch:Brand Blue@50" && near (el.stroke.width, 2) && el.stroke.color == "swatch:Black");
    assert (near (el.opacity, 0.75) && el.wrap == WrapMode.BOUNDING_BOX);
    assert (el.shadow.enabled && near (el.shadow.dx, 4) && near (el.shadow.dy, 5) && near (el.shadow.blur, 7) && near (el.shadow.opacity, 0.5));
    var rect = (ShapeItem) items[3];
    assert (rect.shape == ShapeKind.RECT && near (rect.rotation, 90) && rect.locked);
    assert (near (rect.x, 225) && near (rect.y, 525) && near (rect.w, 100) && near (rect.h, 50));
    var tl = rect.to_page (0, 0);
    assert (near (tl.x, 300) && near (tl.y, 500));
    assert (rect.fill.color == "swatch:Pantone 185 C");
    var line = (ShapeItem) items[4];
    assert (line.shape == ShapeKind.LINE && near (line.x, 50) && near (line.y, 700) && near (line.w, 100) && near (line.h, 0) && line.stroke.dash == DashKind.DASH);
    var tri = (ShapeItem) items[5];
    assert (tri.shape == ShapeKind.PATH && tri.points.size == 3 && near (tri.points[2].x, 0.5) && near (tri.points[2].y, 1) && tri.closed);
    var g = (GroupItem) items[6];
    assert (g.children.size == 2);
    assert (near (g.children[1].x, 460) && near (g.children[1].y, 660));
    assert (g.children[1].corner == CornerKind.ROUNDED && near (g.children[1].corner_radius, 6));
    assert (near (g.x, 400) && near (g.w, 100));
    var tb = (TableItem) p.pages[1].items[1];
    assert (tb.rows == 2 && tb.cols == 2 && near (tb.col_w[1], 70) && near (tb.row_h[1], 30));
    assert (tb.cells[0][0].story.plain_text () == "A1" && tb.cells[1][1].story.plain_text () == "B2");
    assert (tb.cells[1][1].fill == "swatch:Web Orange");
    assert (p.pages[1].items.size == 2);
}

void test_fixture_gzip () {
    SlaReader r;
    var p = read_fixture ("brochure.sla.gz", out r);
    assert (p.pages.size == 2);
    assert (p.swatch ("Brand Blue") != null);
    uint8[] data;
    try {
        FileUtils.get_data (Path.build_filename (fixtures_dir (), "brochure.sla.gz"), out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (FileKind.sniff (data) == FileKind.SLA);
}

void test_fixture_legacy () {
    SlaReader r;
    var p = read_fixture ("legacy.sla", out r);
    assert (p.pages.size == 1 && p.settings.facing && p.settings.units == "in");
    var black = p.swatch ("Black");
    assert (black.model == ColorModel.CMYK && near (black.k, 1) && near (black.c, 0));
    var red = p.swatch ("Red");
    assert (red.model == ColorModel.RGB && near (red.r, 1) && near (red.g, 0));
    var deep = p.swatch ("Deep");
    assert (deep.spot && near (deep.c, 1) && near (deep.m, 128 / 255.0));
    var basic = p.styles.find_paragraph (StyleSheet.BASIC);
    assert (near (basic.para.leading, 0) && basic.chars.font == "Liberation Serif");
    var f1 = (TextFrame) p.pages[0].items[0];
    var f2 = (TextFrame) p.pages[0].items[1];
    assert (f1.story == f2.story);
    var st = p.stories[f1.story];
    assert (st.paras.size == 2 && para_text (st, 0) == "Hello legacy" && para_text (st, 1) == "Second line");
    assert (st.paras[0].runs[0].fmt.color == "swatch:Red");
    assert (st.frames.size == 2 && st.frames[0] == f1.id);
    assert (near (f1.x, 36) && near (f1.y, 36));
}

void test_invalid () {
    var r = new SlaReader ();
    bool failed = false;
    try {
        r.read ("<html><body/></html>".data);
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    failed = false;
    try {
        r.read ("not xml at all".data);
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
}

Publication build_sample () {
    var s = new DocSettings ();
    s.width = 420;
    s.height = 595;
    s.set_bleed (9);
    s.margin_top = 30;
    s.margin_bottom = 40;
    s.margin_inside = 25;
    s.margin_outside = 35;
    s.units = "pt";
    var p = Publication.create (s, 2);
    p.base_dir = fixtures_dir ();
    p.meta.title = "Round Trip";
    p.meta.author = "Tester";
    p.swatches.add (new Swatch.cmyk ("Teal", 0.8, 0.1, 0.4, 0.05));
    p.swatches.add (new Swatch.cmyk ("Gold Spot", 0, 0.2, 0.9, 0.1, true));
    p.swatches.add (new Swatch.rgb ("Screen Pink", 1, 0.4, 0.7));
    var l2 = new Layer (p.next_id (), "Artwork");
    l2.printable = false;
    p.layers.add (l2);
    var title = new ParagraphStyle ("Title", StyleSheet.BASIC);
    title.chars.size = 30;
    title.chars.bold = 1;
    title.chars.color = "swatch:Teal";
    title.para.align = (int) TextAlign.CENTER;
    title.para.space_after = 10;
    p.styles.paragraph.add (title);
    var sub = new ParagraphStyle ("Title Small", "Title");
    sub.chars.size = 18;
    sub.chars.italic = 1;
    p.styles.paragraph.add (sub);
    var body = p.styles.find_paragraph ("Body Text");
    var tabs = new Gee.ArrayList<TabStop> ();
    tabs.add (new TabStop (150, TabKind.RIGHT, "."));
    tabs.add (new TabStop (60, TabKind.CENTER));
    body.para.tabs = TabStop.serialize (tabs);
    var hi = new CharacterStyle ("Highlight");
    hi.chars.color = "swatch:Gold Spot@60";
    hi.chars.underline = 1;
    p.styles.character.add (hi);

    var master = p.masters[0];
    var mf = p.add_text_frame (master.items, 300, 560, 80, 20);
    var ms = p.stories[mf.story];
    ms.paras.clear ();
    var mp = new Paragraph ("Basic Paragraph");
    mp.runs.add (new Run ("Page "));
    mp.runs.add (new Run.field_run (Fields.PAGE));
    mp.runs.add (new Run (" of "));
    mp.runs.add (new Run.field_run (Fields.PAGES));
    ms.paras.add (mp);

    var f1 = p.add_text_frame (p.pages[0].items, 30, 40, 200, 150);
    f1.columns = 2;
    f1.gutter = 10;
    f1.inset_left = 3;
    f1.inset_top = 4;
    f1.valign = 2;
    var st = p.stories[f1.story];
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text ("Welcome", "Title"));
    var p2 = new Paragraph ("Body Text");
    p2.runs.add (new Run ("Plain then "));
    var hr = new Run ("golden");
    hr.cstyle = "Highlight";
    p2.runs.add (hr);
    var br = new Run (" bold\tend");
    br.fmt.bold = 1;
    br.fmt.size = 12.5;
    p2.runs.add (br);
    p2.fmt.first_indent = 8;
    p2.fmt.drop_lines = 2;
    p2.fmt.drop_chars = 1;
    st.paras.add (p2);
    st.paras.add (new Paragraph.with_text ("Line one\u2028line two", "Title Small"));
    var p4 = new Paragraph.with_text ("Numbered", "Numbered List");
    st.paras.add (p4);
    var f2 = p.add_text_frame (p.pages[1].items, 30, 60, 200, 200, st);
    f2.story = st.id;

    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 250;
    im.y = 40;
    im.w = 120;
    im.h = 90;
    im.layer = p.layers[0].id;
    im.link = Path.build_filename (fixtures_dir (), "photo.png");
    im.fit = FitMode.MANUAL;
    im.img_scale = 1.5;
    im.img_x = -6;
    im.img_y = 4;
    im.stroke = new Stroke.with ("swatch:Black", 1.5);
    p.pages[0].items.add (im);

    var el = new ShapeItem (ShapeKind.ELLIPSE);
    el.id = p.next_id ();
    el.x = 60;
    el.y = 250;
    el.w = 90;
    el.h = 70;
    el.layer = l2.id;
    el.fill = new Fill.solid ("swatch:Teal@40");
    el.wrap = WrapMode.CONTOUR;
    el.wrap_offset = 6;
    el.opacity = 0.8;
    p.pages[0].items.add (el);

    var rr = new ShapeItem (ShapeKind.RECT);
    rr.id = p.next_id ();
    rr.x = 200;
    rr.y = 300;
    rr.w = 120;
    rr.h = 40;
    rr.rotation = 30;
    rr.layer = p.layers[0].id;
    rr.fill = new Fill.solid ("#336699");
    rr.stroke = new Stroke.with ("swatch:Screen Pink", 3);
    rr.stroke.dash = DashKind.DOT;
    rr.corner = CornerKind.ROUNDED;
    rr.corner_radius = 8;
    rr.shadow.enabled = true;
    rr.shadow.dx = 2;
    rr.shadow.dy = 3;
    rr.shadow.blur = 5;
    rr.shadow.opacity = 0.4;
    rr.locked = true;
    p.pages[0].items.add (rr);

    var star = new ShapeItem (ShapeKind.STAR);
    star.id = p.next_id ();
    star.x = 300;
    star.y = 400;
    star.w = 60;
    star.h = 60;
    star.sides = 5;
    star.layer = p.layers[0].id;
    star.fill = new Fill.linear ("swatch:Teal", "swatch:Gold Spot", 0);
    p.pages[0].items.add (star);

    var line = new ShapeItem (ShapeKind.LINE);
    line.id = p.next_id ();
    line.x = 40;
    line.y = 500;
    line.w = 100;
    line.h = 30;
    line.line_reverse = true;
    line.layer = p.layers[0].id;
    line.stroke = new Stroke.with ("swatch:Black", 2);
    line.stroke.arrow_end = 1;
    p.pages[1].items.add (line);

    var tb = new TableItem (2, 3);
    tb.id = p.next_id ();
    tb.x = 40;
    tb.y = 320;
    tb.w = 180;
    tb.h = 60;
    tb.layer = p.layers[0].id;
    tb.init_cells (p);
    tb.cells[0][0].story.paras[0].runs[0].text = "Name";
    tb.cells[1][2].story.paras[0].runs[0].text = "42";
    tb.cells[1][2].fill = "swatch:Gold Spot";
    tb.merge (0, 1, 0, 2);
    p.pages[1].items.add (tb);

    var g = new GroupItem ();
    g.id = p.next_id ();
    g.layer = p.layers[0].id;
    var a = new ShapeItem (ShapeKind.RECT);
    a.id = p.next_id ();
    a.x = 250;
    a.y = 450;
    a.w = 30;
    a.h = 30;
    a.layer = p.layers[0].id;
    a.fill = new Fill.solid ("swatch:Black");
    var b = new ShapeItem (ShapeKind.ELLIPSE);
    b.id = p.next_id ();
    b.x = 300;
    b.y = 490;
    b.w = 40;
    b.h = 20;
    b.layer = p.layers[0].id;
    b.fill = new Fill.solid ("swatch:Screen Pink");
    g.children.add (a);
    g.children.add (b);
    g.fit_children ();
    p.pages[1].items.add (g);

    p.sections[0].style = NumberStyle.ARABIC;
    var sec = new Section (1);
    sec.style = NumberStyle.ROMAN_UPPER;
    sec.start_number = 5;
    sec.name = "Back";
    p.sections.add (sec);
    p.pages[0].guides.add (new Guide (true, 123.5));
    p.pages[1].guides.add (new Guide (false, 77));
    return p;
}

void test_round_trip_document () {
    var src = build_sample ();
    SlaReader r;
    var p = round_trip (src, out r);
    assert (p.pages.size == 2);
    assert (near (p.settings.width, 420) && near (p.settings.height, 595));
    assert (near (p.settings.bleed_top, 9) && near (p.settings.bleed_outside, 9));
    assert (near (p.settings.margin_inside, 25) && near (p.settings.margin_outside, 35) && near (p.settings.margin_bottom, 40));
    assert (p.settings.units == "pt");
    assert (p.meta.title == "Round Trip" && p.meta.author == "Tester");
    assert (p.layers.size == 2 && p.layers[1].name == "Artwork" && !p.layers[1].printable);
    assert (p.masters.size == 1 && p.masters[0].name == src.masters[0].name && p.masters[0].items.size == 1);
    assert (p.pages[0].master == "A" && p.pages[1].master == "A");
    assert (p.sections.size == 2 && p.sections[1].start_page == 1 && p.sections[1].style == NumberStyle.ROMAN_UPPER && p.sections[1].start_number == 5);
    assert (p.page_label (1) == "V");
    assert (p.pages[0].guides.size == 1 && p.pages[0].guides[0].vertical && near (p.pages[0].guides[0].pos, 123.5));
    assert (p.pages[1].guides.size == 1 && !p.pages[1].guides[0].vertical && near (p.pages[1].guides[0].pos, 77));
    var mt = (TextFrame) p.masters[0].items[0];
    var ms = p.stories[mt.story];
    assert (ms.fields ().contains (Fields.PAGE) && ms.fields ().contains (Fields.PAGES));
    assert (ms.plain_text ().has_prefix ("Page "));
}

void test_round_trip_swatches_styles () {
    var src = build_sample ();
    SlaReader r;
    var p = round_trip (src, out r);
    foreach (var sw in src.swatches) {
        var o = p.swatch (sw.name);
        assert (o != null);
        assert (o.model == sw.model && o.spot == sw.spot);
        if (sw.model == ColorModel.CMYK) assert (near (o.c, sw.c, 0.001) && near (o.m, sw.m, 0.001) && near (o.y, sw.y, 0.001) && near (o.k, sw.k, 0.001));
        else assert (near (o.r, sw.r, 0.003) && near (o.g, sw.g, 0.003) && near (o.b, sw.b, 0.003));
    }
    foreach (var ps in src.styles.paragraph) {
        var o = p.styles.find_paragraph (ps.name);
        assert (o != null);
        assert (o.based_on == ps.based_on);
        var a1 = ParaFormat.defaults ();
        var c1 = CharFormat.defaults ();
        src.styles.resolve_paragraph (ps.name, a1, c1);
        var a2 = ParaFormat.defaults ();
        var c2 = CharFormat.defaults ();
        p.styles.resolve_paragraph (ps.name, a2, c2);
        assert (a1.align == a2.align);
        assert (near (a1.leading, a2.leading) && near (a1.space_after, a2.space_after) && near (a1.first_indent, a2.first_indent) && near (a1.left_indent, a2.left_indent));
        assert (a1.list_type == a2.list_type);
        assert (c1.font == c2.font && near (c1.size, c2.size) && c1.bold == c2.bold && c1.italic == c2.italic && c1.color == c2.color);
        assert (TabStop.serialize (TabStop.parse (a1.tabs)) == TabStop.serialize (TabStop.parse (a2.tabs)));
    }
    var hi = p.styles.find_character ("Highlight");
    assert (hi != null && hi.chars.underline == 1 && hi.chars.color == "swatch:Gold Spot@60");
}

void test_round_trip_text_threading () {
    var src = build_sample ();
    SlaReader r;
    var p = round_trip (src, out r);
    var f1 = (TextFrame) p.pages[0].items[0];
    var f2 = (TextFrame) p.pages[1].items[0];
    assert (f1.story == f2.story);
    var st = p.stories[f1.story];
    var sst = src.stories[((TextFrame) src.pages[0].items[0]).story];
    assert (st.paras.size == sst.paras.size);
    for (int i = 0; i < st.paras.size; i++) {
        assert (st.paras[i].text () == sst.paras[i].text ());
        assert (st.paras[i].style == sst.paras[i].style);
    }
    assert (st.frames.size == 2 && st.frames[0] == f1.id && st.frames[1] == f2.id);
    assert (f1.columns == 2 && near (f1.gutter, 10) && near (f1.inset_left, 3) && near (f1.inset_top, 4) && f1.valign == 2);
    assert (near (f1.x, 30) && near (f1.y, 40) && near (f1.w, 200) && near (f1.h, 150));
    assert (near (f2.x, 30) && near (f2.y, 60));
    Run? golden = null;
    Run? bold = null;
    foreach (var run in st.paras[1].runs) {
        if (run.text == "golden") golden = run;
        if (run.text.has_prefix (" bold")) bold = run;
    }
    assert (golden != null && golden.cstyle == "Highlight");
    assert (bold != null && bold.fmt.bold == 1 && near (bold.fmt.size, 12.5));
    assert (st.paras[1].fmt.drop_lines == 2 && near (st.paras[1].fmt.first_indent, 8));
    var cache = new LayoutCache (p);
    var res = cache.story (st.id);
    assert (res.frames.size == 2);
}

void test_round_trip_graphics () {
    var src = build_sample ();
    SlaReader r;
    var p = round_trip (src, out r);
    var items = p.pages[0].items;
    assert (items.size == 5);
    var im = (ImageFrame) items[1];
    assert (im.link == File.new_for_path (Path.build_filename (fixtures_dir (), "photo.png")).get_path ());
    assert (im.fit == FitMode.MANUAL && near (im.img_scale, 1.5) && near (im.img_x, -6) && near (im.img_y, 4));
    assert (near (im.x, 250) && near (im.y, 40) && near (im.w, 120) && near (im.h, 90));
    assert (im.stroke.color == "swatch:Black" && near (im.stroke.width, 1.5));
    var el = (ShapeItem) items[2];
    assert (el.shape == ShapeKind.ELLIPSE && el.wrap == WrapMode.CONTOUR && near (el.wrap_offset, 6));
    assert (el.fill.color == "swatch:Teal@40" && near (el.opacity, 0.8));
    assert (el.layer == p.layers[1].id);
    var rr = (ShapeItem) items[3];
    var srr = (ShapeItem) src.pages[0].items[3];
    assert (near (rr.x, srr.x) && near (rr.y, srr.y) && near (rr.w, srr.w) && near (rr.h, srr.h) && near (rr.rotation, 30));
    assert (rr.fill.color == "#336699");
    assert (rr.stroke.color == "swatch:Screen Pink" && rr.stroke.dash == DashKind.DOT && near (rr.stroke.width, 3));
    assert (rr.corner == CornerKind.ROUNDED && near (rr.corner_radius, 8));
    assert (rr.shadow.enabled && near (rr.shadow.dx, 2) && near (rr.shadow.opacity, 0.4) && rr.locked);
    var star = (ShapeItem) items[4];
    var sstar = (ShapeItem) src.pages[0].items[4];
    assert (star.shape == ShapeKind.PATH && star.points.size == 10);
    var o1 = star.outline ();
    var o2 = sstar.outline ();
    for (int i = 0; i < 10; i++) assert (near (o1[i].x, o2[i].x) && near (o1[i].y, o2[i].y));
    assert (star.fill.kind == FillKind.LINEAR && star.fill.stops.size == 2 && star.fill.stops[1].color == "swatch:Gold Spot" && near (star.fill.angle, 0));
    var p1 = p.pages[1].items;
    assert (p1.size == 4);
    var line = (ShapeItem) p1[1];
    assert (line.shape == ShapeKind.LINE && line.line_reverse && near (line.x, 40) && near (line.y, 500) && near (line.w, 100) && near (line.h, 30));
    assert (line.stroke.arrow_end == 1 && near (line.stroke.width, 2));
    var tb = (TableItem) p1[2];
    assert (tb.rows == 2 && tb.cols == 3 && tb.cells[0][0].story.plain_text () == "Name" && tb.cells[1][2].story.plain_text () == "42");
    assert (tb.cells[1][2].fill == "swatch:Gold Spot" && tb.cells[0][1].col_span == 2 && tb.cells[0][2].covered);
    assert (near (tb.x, 40) && near (tb.y, 320) && near (tb.col_w[0], 60));
    var g = (GroupItem) p1[3];
    assert (g.children.size == 2 && near (g.children[1].x, 300) && near (g.children[1].y, 490) && near (g.children[0].x, 250));
}

void test_inline_image () {
    var p = Publication.create ();
    uint8[] png;
    try {
        FileUtils.get_data (Path.build_filename (fixtures_dir (), "photo.png"), out png);
    } catch (Error e) {
        assert_not_reached ();
    }
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.w = 50;
    im.h = 50;
    im.layer = p.layers[0].id;
    im.media = p.add_media (png, "photo.png");
    im.fit = FitMode.FIT;
    p.pages[0].items.add (im);
    string xml;
    try {
        xml = new SlaWriter (p).write ();
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (xml.contains ("isInlineImage=\"1\""));
    var r = new SlaReader ();
    Publication q;
    try {
        q = r.read (xml.data);
    } catch (Error e) {
        assert_not_reached ();
    }
    var qi = (ImageFrame) q.pages[0].items[0];
    assert (qi.media != "" && qi.fit == FitMode.FIT);
    var bytes = q.media[qi.media].get_data ();
    assert (bytes.length == png.length && Memory.cmp (bytes, png, png.length) == 0);
    var inf = ImageStore.get_default ().info (q, qi);
    assert (inf != null && inf.width == 40 && inf.height == 20);
}

void test_writer_structure () {
    var src = build_sample ();
    string xml;
    try {
        xml = new SlaWriter (src).write ();
    } catch (Error e) {
        assert_not_reached ();
    }
    Xml.Doc* doc = Xml.Parser.read_memory (xml, xml.length);
    assert (doc != null);
    var root = doc->get_root_element ();
    assert (root->name == "SCRIBUSUTF8NEW" && XmlIn.attr (root, "Version") == "1.5.8");
    var dn = XmlIn.child (root, "DOCUMENT");
    assert (XmlIn.attr (dn, "ANZPAGES") == "2");
    assert (XmlIn.elements (dn, "PAGE").size == 2);
    assert (XmlIn.elements (dn, "MASTERPAGE").size == 1);
    assert (XmlIn.elements (dn, "MASTEROBJECT").size == 1);
    assert (XmlIn.elements (dn, "LAYERS").size == 2);
    int colors = XmlIn.elements (dn, "COLOR").size;
    assert (colors == src.swatches.size + 1);
    bool adhoc = false;
    foreach (var c in XmlIn.elements (dn, "COLOR")) if (XmlIn.attr (c, "NAME") == "FromPublish #336699") adhoc = true;
    assert (adhoc);
    int defaults = 0;
    foreach (var s in XmlIn.elements (dn, "STYLE")) if (XmlIn.attr (s, "DefaultStyle") == "1") defaults++;
    assert (defaults == 1);
    var pages = XmlIn.elements (dn, "PAGE");
    assert (near (double.parse (XmlIn.attr (pages[1], "PAGEYPOS")), 20 + 595 + 40));
    int with_story = 0;
    foreach (var o in XmlIn.elements (dn, "PAGEOBJECT")) {
        if (XmlIn.attr (o, "PTYPE") != "4") continue;
        var st = XmlIn.child (o, "StoryText");
        assert (st != null);
        if (XmlIn.elements (st, "ITEXT").size > 0) with_story++;
    }
    assert (with_story == 1);
    delete doc;
}

void test_facing_masters () {
    var s = new DocSettings ();
    s.facing = true;
    var p = Publication.create (s, 3);
    var m = p.masters[0];
    var r1 = new ShapeItem (ShapeKind.RECT);
    r1.id = p.next_id ();
    r1.x = 10;
    r1.y = 10;
    r1.w = 20;
    r1.h = 20;
    r1.layer = p.layers[0].id;
    m.items.add (r1);
    var l1 = new ShapeItem (ShapeKind.ELLIPSE);
    l1.id = p.next_id ();
    l1.x = 50;
    l1.y = 10;
    l1.w = 20;
    l1.h = 20;
    l1.layer = p.layers[0].id;
    m.left_items.add (l1);
    SlaReader r;
    var q = round_trip (p, out r);
    assert (q.settings.facing);
    assert (q.masters.size == 1);
    assert (q.masters[0].items.size == 1 && q.masters[0].left_items.size == 1);
    assert (((ShapeItem) q.masters[0].left_items[0]).shape == ShapeKind.ELLIPSE);
    assert (q.pages.size == 3 && q.pages[1].master == q.masters[0].id);
    assert (q.master_items_for (1).size == 1 && q.master_items_for (1)[0] is ShapeItem && ((ShapeItem) q.master_items_for (1)[0]).shape == ShapeKind.ELLIPSE);
}

void test_document_open_dispatch () {
    string note;
    uint8[] data;
    try {
        FileUtils.get_data (Path.build_filename (fixtures_dir (), "brochure.sla"), out data);
        var p = Document.load_bytes (data, "brochure.sla", out note);
        assert (p.pages.size == 2);
        assert (note.contains ("render frames"));
        var bytes = Document.serialize (p, FileKind.SLA);
        var q = Document.load_bytes (bytes, "copy.sla", out note);
        assert (q.pages.size == 2);
    } catch (Error e) {
        error ("%s", e.message);
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/sla/fixture/document", test_fixture_document);
    Test.add_func ("/sla/fixture/colors", test_fixture_colors);
    Test.add_func ("/sla/fixture/styles", test_fixture_styles);
    Test.add_func ("/sla/fixture/layers-masters", test_fixture_layers_masters);
    Test.add_func ("/sla/fixture/text", test_fixture_text);
    Test.add_func ("/sla/fixture/graphics", test_fixture_graphics);
    Test.add_func ("/sla/fixture/gzip", test_fixture_gzip);
    Test.add_func ("/sla/fixture/legacy", test_fixture_legacy);
    Test.add_func ("/sla/invalid", test_invalid);
    Test.add_func ("/sla/roundtrip/document", test_round_trip_document);
    Test.add_func ("/sla/roundtrip/swatches-styles", test_round_trip_swatches_styles);
    Test.add_func ("/sla/roundtrip/text-threading", test_round_trip_text_threading);
    Test.add_func ("/sla/roundtrip/graphics", test_round_trip_graphics);
    Test.add_func ("/sla/roundtrip/inline-image", test_inline_image);
    Test.add_func ("/sla/roundtrip/facing-masters", test_facing_masters);
    Test.add_func ("/sla/writer/structure", test_writer_structure);
    Test.add_func ("/sla/document-dispatch", test_document_open_dispatch);
    return Test.run ();
}
