using Singularity.Apps.Publish;

string fixtures_root () {
    return Environment.get_variable ("PUBLISH_FIXTURES") ?? "fixtures";
}

bool near (double a, double b, double eps = 0.01) {
    return Math.fabs (a - b) <= eps;
}

void collect (string base_dir, string rel, Gee.ArrayList<string> files) {
    try {
        var d = Dir.open (Path.build_filename (base_dir, rel));
        string? n;
        while ((n = d.read_name ()) != null) {
            string r = rel == "" ? n : rel + "/" + n;
            if (FileUtils.test (Path.build_filename (base_dir, r), FileTest.IS_DIR)) collect (base_dir, r, files);
            else files.add (r);
        }
    } catch (FileError e) {
        error ("cannot read fixture: %s", e.message);
    }
}

uint8[] package (string name) {
    string dir = Path.build_filename (fixtures_root (), "idml", name);
    var files = new Gee.ArrayList<string> ();
    collect (dir, "", files);
    files.sort ();
    var zip = new ZipWriter ();
    try {
        uint8[] data;
        FileUtils.get_data (Path.build_filename (dir, "mimetype"), out data);
        zip.add ("mimetype", data, false);
        foreach (string f in files) {
            if (f == "mimetype") continue;
            FileUtils.get_data (Path.build_filename (dir, f), out data);
            zip.add (f, data);
        }
    } catch (Error e) {
        error ("cannot zip fixture: %s", e.message);
    }
    return zip.finish ();
}

Publication? cached = null;
string? cached_notes = null;

Publication harbour () {
    if (cached != null) return cached;
    var r = new IdmlReader ();
    try {
        cached = r.read (package ("harbour"));
    } catch (Error e) {
        error ("import failed: %s", e.message);
    }
    cached_notes = r.notes ();
    return cached;
}

Item item_at (Page p, int i) {
    return p.items[i];
}

void test_document_setup () {
    var p = harbour ();
    var s = p.settings;
    assert (near (s.width, 612) && near (s.height, 792));
    assert (s.facing && !s.start_left);
    assert (near (s.bleed_top, 9) && near (s.bleed_bottom, 9) && near (s.bleed_inside, 0) && near (s.bleed_outside, 9));
    assert (near (s.slug, 18));
    assert (near (s.margin_top, 36) && near (s.margin_bottom, 54) && near (s.margin_inside, 45) && near (s.margin_outside, 36));
    assert (s.columns == 2 && near (s.gutter, 12));
    assert (s.page_size == "letter");
    assert (p.meta.title == "Harbour News");
    assert (p.meta.author == "Port Office");
    assert (p.pages.size == 3);
}

void test_masters_and_sections () {
    var p = harbour ();
    assert (p.pages[0].master == "A" && p.pages[1].master == "A" && p.pages[2].master == "B");
    var a = p.master ("A");
    var b = p.master ("B");
    assert (a != null && b != null);
    assert (a.name == "Parent" && b.name == "Chapter");
    assert (b.based_on == "A");
    assert (a.left_items.size == 1 && a.items.size == 1);
    var lf = (TextFrame) a.left_items[0];
    assert (near (lf.x, 36) && near (lf.y, 750) && near (lf.w, 100) && near (lf.h, 18));
    var rf = (TextFrame) a.items[0];
    assert (near (rf.x, 476) && near (rf.y, 750));
    assert (p.story (rf.story).fields ().contains (Fields.PAGE));
    assert (p.story (rf.story).paras[0].text ().has_prefix ("Page "));
    assert (b.items.size == 1 && b.left_items.size == 1);
    assert (b.left_items[0].id != b.items[0].id);
    var band = b.items[0];
    assert (near (band.x, 0) && near (band.y, 0) && near (band.w, 612) && near (band.h, 40));
    assert (p.is_left_page (1) && !p.is_left_page (0) && !p.is_left_page (2));
    var masters2 = p.master_items_for (2);
    assert (masters2.size == 2);
    assert (p.page_label (0) == "1" && p.page_label (1) == "2");
    assert (p.page_label (2) == "x");
    assert (p.section_for (2).name == "Timetables");
}

void test_layers () {
    var p = harbour ();
    assert (p.layers.size == 2);
    assert (p.layers[0].name == "Background" && p.layers[1].name == "Text");
    assert (p.layers[0].locked && !p.layers[0].printable);
    assert (!p.layers[1].locked && p.layers[1].printable);
    assert (item_at (p.pages[0], 0).layer == p.layers[1].id);
    assert (item_at (p.pages[0], 1).layer == p.layers[0].id);
}

void test_frames_and_transforms () {
    var p = harbour ();
    var pg = p.pages[0];
    assert (pg.items.size == 5);
    var tf = pg.items[0] as TextFrame;
    assert (tf != null);
    assert (near (tf.x, 36) && near (tf.y, 36) && near (tf.w, 540) && near (tf.h, 364));
    assert (tf.columns == 2 && near (tf.gutter, 12) && near (tf.inset_top, 4) && near (tf.inset_right, 4));
    var rect = pg.items[1] as ShapeItem;
    assert (rect != null && rect.shape == ShapeKind.RECT);
    assert (near (rect.x, 256) && near (rect.y, 75) && near (rect.w, 100) && near (rect.h, 50));
    assert (near (rect.rotation, 30, 0.001) && !rect.flip_h && !rect.flip_v);
    var corner = rect.to_page (0, 0);
    assert (near (corner.x, 306 - 50 * 0.8660254 + 25 * 0.5) && near (corner.y, 100 - 50 * 0.5 - 25 * 0.8660254));
    assert (rect.fill.kind == FillKind.SOLID && rect.fill.color == "swatch:Magenta Ink@50");
    assert (rect.stroke.color == ColorRef.BLACK && near (rect.stroke.width, 2));
    assert (rect.shadow.enabled && near (rect.shadow.dx, 4) && near (rect.shadow.dy, 5) && near (rect.shadow.opacity, 0.6) && near (rect.shadow.blur, 6));
    var oval = pg.items[2] as ShapeItem;
    assert (oval != null && oval.shape == ShapeKind.ELLIPSE);
    assert (near (oval.x, 350) && near (oval.y, 200) && near (oval.w, 100) && near (oval.h, 100));
    assert (oval.wrap == WrapMode.CONTOUR && near (oval.wrap_offset, 6));
    assert (near (oval.opacity, 0.8));
    assert (oval.fill.color == "swatch:PANTONE 185 C");
    var p2 = p.pages[1];
    var tf2 = p2.items[0] as TextFrame;
    assert (tf2 != null && near (tf2.x, 36) && near (tf2.y, 36) && near (tf2.w, 540) && near (tf2.h, 660) && tf2.columns == 3);
}

void test_images () {
    var p = harbour ();
    var pg = p.pages[0];
    var im = pg.items[3] as ImageFrame;
    assert (im != null);
    assert (near (im.x, 36) && near (im.y, 300) && near (im.w, 200) && near (im.h, 150));
    assert (im.fit == FitMode.MANUAL);
    assert (near (im.img_x, 10) && near (im.img_y, 20) && near (im.img_scale, 0.5));
    assert (im.link == "/Users/designer/Photos/harbour view.jpg");
    assert (im.media == "");
    assert (im.wrap == WrapMode.BOUNDING_BOX && near (im.wrap_offset, 8));
    assert (im.stroke.dash == DashKind.DASH && near (im.stroke.width, 0.5));
    assert (ImageStore.status (p, im) == LinkStatus.MISSING);
    var em = pg.items[4] as ImageFrame;
    assert (em != null && em.link == "" && em.media != "");
    assert (p.media.has_key (em.media));
    assert (near (em.img_scale, 10) && near (em.img_x, 0) && near (em.img_y, 0));
    assert (em.corner == CornerKind.ROUNDED && near (em.corner_radius, 6));
    var info = ImageStore.get_default ().info (p, em);
    assert (info != null && info.width == 8 && info.height == 6);
}

void test_threading () {
    var p = harbour ();
    var a = (TextFrame) p.pages[0].items[0];
    var b = (TextFrame) p.pages[1].items[0];
    assert (a.story == b.story);
    var st = p.story (a.story);
    assert (st.frames.size == 2 && st.frames[0] == a.id && st.frames[1] == b.id);
    var frames = p.thread_frames (a.story);
    assert (frames.size == 2 && frames[0] == a && frames[1] == b);
    var cache = new LayoutCache (p);
    var res = cache.story (a.story);
    assert (res.frames[0].lines.size > 0);
    assert (res.frames[1].lines.size > 0);
    assert (!res.overset);
}

void test_story_text () {
    var p = harbour ();
    var st = p.story (((TextFrame) p.pages[0].items[0]).story);
    assert (st.paras.size == 17);
    assert (st.paras[0].text () == "Harbour News" && st.paras[0].style == "Heading");
    assert (st.paras[1].text () == "The ferry schedule changes next week." && st.paras[1].style == "Lead");
    assert (st.paras[2].text () == "Visitors should check the new timetable before travelling.");
    assert (st.paras[2].style == "Body" && st.paras[2].fmt.align == (int) TextAlign.JUSTIFY_ALL);
    Run? emph = null;
    foreach (var r in st.paras[2].runs) if (r.cstyle == "Emphasis") emph = r;
    assert (emph != null && emph.text == "new timetable" && emph.fmt.color == "swatch:Magenta Ink");
    assert (st.paras[3].text () == "Arrivals\t12" && st.paras[3].style == "TOC");
    assert (st.paras[4].text ().has_prefix ("Paragraph 1. Harbour works"));
    assert (st.paras[16].text () == "End of the news." && st.paras[16].style == "Caption");
}

void test_styles () {
    var p = harbour ();
    var ss = p.styles;
    var h = ss.find_paragraph ("Heading");
    assert (h != null && h.based_on == "Body" && h.next == "Body");
    assert (ss.find_paragraph ("Body").based_on == StyleSheet.BASIC);
    var pf = ParaFormat.defaults ();
    var cf = CharFormat.defaults ();
    ss.resolve_paragraph ("Heading", pf, cf);
    assert (near (cf.size, 24) && cf.bold == 1 && cf.font == "Inter");
    assert (near (pf.leading, 28) && near (pf.first_indent, 0) && pf.hyphenate == 0 && near (pf.space_after, 8));
    assert (pf.text_align () == TextAlign.LEFT);
    assert (cf.color == "swatch:PANTONE 185 C");
    pf = ParaFormat.defaults ();
    cf = CharFormat.defaults ();
    ss.resolve_paragraph ("Lead", pf, cf);
    assert (pf.drop_lines == 3 && pf.drop_chars == 1 && near (pf.leading, 14) && near (cf.size, 10) && cf.font == "Inter");
    assert (pf.text_align () == TextAlign.JUSTIFY);
    pf = ParaFormat.defaults ();
    cf = CharFormat.defaults ();
    ss.resolve_paragraph (StyleSheet.BASIC, pf, cf);
    assert (near (cf.size, 12) && cf.font == "Inter" && near (pf.leading, 0));
    pf = ParaFormat.defaults ();
    cf = CharFormat.defaults ();
    ss.resolve_paragraph ("TOC", pf, cf);
    var tabs = TabStop.parse (pf.tabs);
    assert (tabs.size == 1 && near (tabs[0].pos, 200) && tabs[0].kind == TabKind.RIGHT && tabs[0].leader == ".");
    pf = ParaFormat.defaults ();
    cf = CharFormat.defaults ();
    ss.resolve_paragraph ("Footer", pf, cf);
    assert (cf.caps == 1 && near (cf.tracking, 50) && near (cf.size, 8));
    var cap = ss.find_paragraph ("Caption");
    assert (cap != null && cap.based_on == "Body" && cap.chars.italic == 1);
    var strong = ss.find_character ("Strong");
    assert (strong != null && strong.based_on == "Emphasis");
    var sf = new CharFormat ();
    ss.resolve_character ("Strong", sf);
    assert (sf.bold == 1 && sf.italic == 1);
    var ef = new CharFormat ();
    ss.resolve_character ("Emphasis", ef);
    assert (ef.italic == 1 && ef.bold == 0);
}

void test_swatches () {
    var p = harbour ();
    var mag = p.swatch ("Magenta Ink");
    assert (mag != null && mag.model == ColorModel.CMYK && !mag.spot && near (mag.m, 1) && near (mag.c, 0) && near (mag.k, 0));
    var pan = p.swatch ("PANTONE 185 C");
    assert (pan != null && pan.spot && near (pan.m, 0.91) && near (pan.y, 0.76));
    var sky = p.swatch ("Sky");
    assert (sky != null && sky.model == ColorModel.RGB && near (sky.r, 40 / 255.0) && near (sky.b, 220 / 255.0));
    assert (p.swatch ("Paper") != null && p.swatch ("Registration") != null);
    int blacks = 0;
    foreach (var s in p.swatches) if (s.name == "Black") blacks++;
    assert (blacks == 1);
    var c = p.resolve ("swatch:Magenta Ink@30");
    assert (c.g > 0.6);
}

void test_page_three () {
    var p = harbour ();
    var pg = p.pages[2];
    assert (pg.items.size == 4);
    assert (pg.items[0] is TextFrame);
    var tb = pg.items[1] as TableItem;
    assert (tb != null);
    assert (tb.rows == 3 && tb.cols == 3 && tb.header_rows == 1);
    assert (near (tb.col_w[0], 120) && near (tb.col_w[1], 100) && near (tb.row_h[2], 22));
    assert (near (tb.w, 320) && near (tb.h, 62));
    assert (near (tb.x, 40) && near (tb.y, 40));
    assert (tb.wrap == WrapMode.JUMP);
    assert (tb.cells[0][0].story.plain_text () == "Route" && tb.cells[0][0].fill == "swatch:Magenta Ink@30");
    assert (tb.cells[1][2].story.plain_text () == "08:40");
    assert (tb.cells[2][1].story.plain_text () == "Cancelled" && tb.cells[2][1].col_span == 2);
    assert (tb.cells[2][2].covered);
    var tst = p.story (((TextFrame) pg.items[0]).story);
    assert (tst.paras.size == 2);
    assert (tst.paras[0].text () == "Timetable");
    assert (tst.paras[1].text () == "Times may change in bad weather.");
    var g = pg.items[2] as GroupItem;
    assert (g != null && g.children.size == 2);
    assert (g.layer == p.layers[0].id);
    var c1 = g.children[0];
    var c2 = g.children[1];
    assert (near (c1.x, 100) && near (c1.y, 400) && near (c1.w, 50) && near (c1.h, 50));
    assert (near (c2.x, 200) && near (c2.y, 400));
    assert (near (g.x, 100) && near (g.w, 150));
    assert (c1.fill.color == "swatch:Magenta Ink@30");
    assert (c2.fill.kind == FillKind.LINEAR && c2.fill.stops.size == 2 && near (c2.fill.angle, 90));
    assert (c2.fill.stops[1].color == "swatch:Sky" && near (c2.fill.stops[1].offset, 1));
    var line = pg.items[3] as ShapeItem;
    assert (line != null && line.shape == ShapeKind.LINE);
    assert (near (line.x, 36) && near (line.y, 300) && near (line.w, 540) && near (line.h, 20) && !line.line_reverse);
    assert (line.stroke.color == "swatch:Sky" && near (line.stroke.width, 1.5) && line.stroke.arrow_end == 1 && line.stroke.arrow_start == 0);
}

void test_notes_and_errors () {
    harbour ();
    assert (cached_notes.contains ("Tables anchored in text were placed as table objects"));
    var zip = new ZipWriter ();
    try {
        zip.add_text ("hello.txt", "x");
    } catch (Error e) {
        assert_not_reached ();
    }
    bool failed = false;
    try {
        new IdmlReader ().read (zip.finish ());
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    assert (IdmlReader.uri_to_path ("file:C:/Docs/a%20b.png") == "C:/Docs/a b.png");
    assert (IdmlReader.uri_to_path ("file:///tmp/x.png") == "/tmp/x.png");
}

void test_catalogue_extended () {
    var r = new IdmlReader ();
    Publication p;
    try {
        p = r.read (package ("catalogue"));
    } catch (Error e) {
        error ("import failed: %s", e.message);
    }
    string notes = r.notes ();
    assert (!notes.contains ("Footnotes are not supported"));
    assert (!notes.contains ("Nested styles are not supported"));
    assert (!notes.contains ("Object styles were applied"));
    var entry = p.styles.find_paragraph ("Entry");
    assert (entry.nested.size == 2);
    assert (entry.nested[0].cstyle == "Lead In" && entry.nested[0].unit == NestedUnit.CHARACTER && entry.nested[0].character == ":" && entry.nested[0].through);
    assert (entry.nested[1].cstyle == "Price" && entry.nested[1].unit == NestedUnit.WORDS && entry.nested[1].count == 2 && !entry.nested[1].through);
    assert (entry.grep.size == 1 && entry.grep[0].pattern == "\\d+ EUR" && entry.grep[0].cstyle == "Price");
    assert (p.object_styles.size == 2);
    ObjectStyle? badge = null;
    foreach (var o in p.object_styles) if (o.name == "Badge") badge = o;
    assert (badge != null && badge.based_on == "Photo Frame");
    Item? photo = null;
    foreach (var it in p.pages[0].items) if (it.object_style == "Photo Frame") photo = it;
    assert (photo != null);
    assert (p.cell_styles.size == 3 && p.table_styles.size == 1);
    var dark = TableStyles.resolve_cell (p, "Dark Head");
    assert (dark.valign == 1 && dark.para_style == "Cell Head" && dark.fill != "");
    var prices = p.table_styles[0];
    assert (prices.name == "Prices" && prices.header_cell == "Head" && prices.body_cell == "Body" && prices.alt_fill != "" && Math.fabs (prices.border_width - 1.5) < 0.01);
    TableItem? table = null;
    foreach (var it in p.pages[0].items) if (it is TableItem) table = (TableItem) it;
    assert (table != null && table.table_style == "Prices");
    assert (table.cell (0, 1).cell_style == "Dark Head" && table.cell (0, 0).cell_style == "");
    assert (table.cell (0, 0).story.paras[0].style == "Cell Head");
    var eff = TableStyles.effective_cell (p, table, 1, 0);
    assert (eff != null && eff.name == "Body" && eff.valign == 2);
    Story? main = null;
    foreach (var st in p.stories.values) if (st.plain_text ().has_prefix ("Teapot")) main = st;
    assert (main != null);
    int foot = 0, anchored = 0;
    foreach (var para in main.paras) foreach (var run in para.runs) {
        if (run.note != null) {
            foot++;
            assert (run.note.plain_text () == "Price includes delivery within the city.");
            assert (run.note.paras[0].style == FootnoteOptions.STYLE);
        }
        if (run.anchor != null) {
            anchored++;
            assert (run.anchor.object_style == "Badge" && Math.fabs (run.anchor.w - 30) < 0.5 && Math.fabs (run.anchor.h - 20) < 0.5);
            assert (run.anchor_spec.inline ());
        }
    }
    assert (foot == 1 && anchored == 1);
    var cache = new LayoutCache (p);
    TextFrame? tf = null;
    foreach (var it in p.pages[0].items) if (it is TextFrame) tf = (TextFrame) it;
    var fr = cache.story (tf.story).frames[0];
    assert (fr.notes.size == 1);
}

void test_indd_preview () {
    var pages = new Gee.ArrayList<Bytes> ();
    foreach (uint32 col in new uint32[] { 0xff0000ffU, 0x00ff00ffU, 0x0000ffffU }) {
        var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 40, 56);
        pb.fill (col);
        uint8[] buf;
        try {
            pb.save_to_buffer (out buf, "jpeg");
        } catch (Error e) {
            error (e.message);
        }
        pages.add (new Bytes (buf));
    }
    var data = InddPreview.synthesize ("Spring Catalogue", 2, 595.276, 841.89, pages);
    assert (InddPreview.is_indd (data) && FileKind.sniff (data) == FileKind.INDD);
    assert (FileKind.from_path ("x.INDD") == FileKind.INDD);
    string note;
    Publication p;
    try {
        p = Document.load_bytes (data, "spring.indd", out note);
    } catch (Error e) {
        error (e.message);
    }
    assert (note.contains ("IDML"));
    assert (p.meta.title == "Spring Catalogue" && p.pages.size == 2);
    assert (Math.fabs (p.settings.width - 595.276) < 0.01);
    var im = p.pages[1].items[0] as ImageFrame;
    assert (im != null && im.locked && p.media.has_key (im.media));
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 60, 80);
    var cr = new Cairo.Context (surf);
    cr.scale (60 / p.settings.width, 80 / p.settings.height);
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_page (cr, 1);
    surf.flush ();
    unowned uint8[] px = surf.get_data ();
    int o = 40 * surf.get_stride () + 30 * 4;
    assert (px[0 + o] > 180 && px[2 + o] < 80);
    bool failed = false;
    try {
        InddPreview.read ("not indd".data);
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
}

void test_writer_round_trip () {
    var p = Publication.create (null, 1);
    var lead = new CharacterStyle ("Lead");
    lead.chars.bold = 1;
    p.styles.character.add (lead);
    var ps = new ParagraphStyle ("Entry", StyleSheet.BASIC);
    var ns = new NestedStyle ("Lead");
    ns.unit = NestedUnit.CHARACTER;
    ns.character = ":";
    ps.nested.add (ns);
    ps.grep.add (new GrepStyle ("Lead", "\\d+"));
    p.styles.paragraph.add (ps);
    var os = new ObjectStyle ("Frame Style");
    os.proto.fill = new Fill.solid (ColorRef.swatch ("Cyan"));
    p.object_styles.add (os);
    var head = new CellStyle ("Head");
    head.valign = 1;
    p.cell_styles.add (head);
    var tsty = new TableStyle ("Grid");
    tsty.header_cell = "Head";
    p.table_styles.add (tsty);
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 200);
    t.object_style = "Frame Style";
    var st = p.story (t.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("Teapot: clay", "Entry");
    para.runs.add (Footnotes.make_run (p, "Made by hand."));
    var badge = new ShapeItem (ShapeKind.RECT);
    badge.id = p.next_id ();
    badge.w = 20;
    badge.h = 10;
    para.runs.add (new Run.anchored (badge, new AnchorSpec ()));
    para.runs.add (new Run (" end"));
    st.paras.add (para);
    var tb = new TableItem (2, 2);
    tb.id = p.next_id ();
    tb.x = 40;
    tb.y = 300;
    tb.w = 200;
    tb.h = 40;
    tb.init_cells (p);
    tb.header_rows = 1;
    tb.cell (0, 0).story.paras[0].runs[0].text = "Item";
    tb.cell (1, 1).story.paras[0].runs[0].text = "45";
    tb.cell (0, 1).cell_style = "Head";
    tb.table_style = "Grid";
    p.pages[0].items.add (tb);
    Publication q;
    try {
        q = new IdmlReader ().read (new IdmlWriter (p).write ());
    } catch (Error e) {
        error (e.message);
    }
    var qps = q.styles.find_paragraph ("Entry");
    assert (qps.nested.size == 1 && qps.nested[0].character == ":" && qps.grep.size == 1 && qps.grep[0].pattern == "\\d+");
    assert (q.object_styles.size == 1 && q.object_styles[0].name == "Frame Style");
    assert (q.cell_styles.size == 1 && q.table_styles.size == 1 && q.table_styles[0].header_cell == "Head");
    TableItem? qt = null;
    TextFrame? qf = null;
    foreach (var it in q.pages[0].items) {
        if (it is TableItem) qt = (TableItem) it;
        if (it is TextFrame && q.story (((TextFrame) it).story).plain_text ().has_prefix ("Teapot")) qf = (TextFrame) it;
    }
    assert (qt != null && qt.rows == 2 && qt.cols == 2 && qt.header_rows == 1 && qt.table_style == "Grid");
    assert (qt.cell (1, 1).story.plain_text () == "45" && qt.cell (0, 1).cell_style == "Head");
    assert (qf != null && qf.object_style == "Frame Style");
    int notes = 0, anchors = 0;
    foreach (var qp in q.story (qf.story).paras) foreach (var r in qp.runs) {
        if (r.note != null) {
            notes++;
            assert (r.note.plain_text () == "Made by hand.");
        }
        if (r.anchor != null) anchors++;
    }
    assert (notes == 1 && anchors == 1);
}

void test_sniff_and_open () {
    var data = package ("harbour");
    assert (FileKind.sniff (data) == FileKind.IDML);
    string note;
    try {
        var p = Document.load_bytes (data, "harbour.idml", out note);
        assert (p.pages.size == 3);
        assert (note != "");
    } catch (Error e) {
        assert_not_reached ();
    }
}

void test_render () {
    var p = harbour ();
    string dir = Path.build_filename (Environment.get_tmp_dir (), "idml-render");
    DirUtils.create_with_parents (dir, 0755);
    var ex = new Exporter (p);
    ex.opts.dpi = 72;
    try {
        var files = ex.export_images (dir, "harbour", "png");
        assert (files.size == 3);
        foreach (string f in files) assert (FileUtils.test (f, FileTest.IS_REGULAR));
        var cache = new LayoutCache (p);
        var mf = (TextFrame) p.master ("A").items[0];
        var fr = cache.frame (mf, true, 0);
        assert (fr != null && fr.lines.size == 1);
        assert (fr.lines[0].layout.get_text ().contains ("1"));
    } catch (Error e) {
        assert_not_reached ();
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/idml/document-setup", test_document_setup);
    Test.add_func ("/idml/masters-sections", test_masters_and_sections);
    Test.add_func ("/idml/layers", test_layers);
    Test.add_func ("/idml/frames-transforms", test_frames_and_transforms);
    Test.add_func ("/idml/images", test_images);
    Test.add_func ("/idml/threading", test_threading);
    Test.add_func ("/idml/story-text", test_story_text);
    Test.add_func ("/idml/catalogue-extended", test_catalogue_extended);
    Test.add_func ("/idml/indd-preview", test_indd_preview);
    Test.add_func ("/idml/writer-round-trip", test_writer_round_trip);
    Test.add_func ("/idml/styles", test_styles);
    Test.add_func ("/idml/swatches", test_swatches);
    Test.add_func ("/idml/page-three", test_page_three);
    Test.add_func ("/idml/notes-errors", test_notes_and_errors);
    Test.add_func ("/idml/sniff-open", test_sniff_and_open);
    Test.add_func ("/idml/render", test_render);
    return Test.run ();
}
