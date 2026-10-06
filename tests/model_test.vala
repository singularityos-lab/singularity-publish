using Singularity.Apps.Publish;

bool near (double a, double b, double eps = 0.01) {
    return (a - b).abs () <= eps;
}

Publication sample () {
    var p = Publication.create (null, 3);
    return p;
}

void test_units () {
    assert (near (Units.from_unit (25.4, "mm"), 72));
    assert (near (Units.to_unit (72, "in"), 1));
    assert (near (Units.parse_length ("10 mm", "pt"), 28.3465, 0.001));
    assert (near (Units.parse_length ("2in", "mm"), 144));
    assert (near (Units.parse_length ("3,5", "cm"), 99.2126, 0.001));
    assert (Units.parse_length ("abc", "mm").is_nan ());
    var a4 = PageSize.find ("a4");
    assert (a4 != null && near (a4.width, 595.2756, 0.01));
    var card = PageSize.find ("card-eu");
    assert (card != null && near (card.width, 85 * Units.PT_PER_MM));
    assert (PageSize.match (a4.height, a4.width).id == "a4");
    var r = Rect (0, 0, 10, 10);
    assert (r.intersects (Rect (5, 5, 10, 10)));
    assert (!r.intersects (Rect (11, 0, 5, 5)));
    assert (Rect (1, 1, 2, 2).inside (r));
}

void test_colors () {
    var p = sample ();
    var c = p.resolve (ColorRef.swatch ("Cyan"));
    assert (near (c.r, 0) && near (c.g, 1, 0.05) && near (c.b, 1, 0.05));
    var tint = p.resolve (ColorRef.swatch ("Black", 50));
    assert (tint.r > 0.3 && tint.r < 0.7);
    assert (ColorRef.tint_of ("swatch:Black@25") == 25);
    assert (ColorRef.swatch_name ("swatch:Red@40") == "Red");
    Rgba h;
    assert (Rgba.parse_hex ("#ff8000", out h) && near (h.g, 0.5, 0.01));
    assert (p.resolve ("cmyk:0,0,0,1").r < 0.05);
    double cc, m, y, k;
    ColorMath.rgb_to_cmyk (1, 0, 0, out cc, out m, out y, out k);
    assert (near (cc, 0) && near (m, 1) && near (y, 1) && near (k, 0));
    var sw = new Swatch.cmyk ("Spot Orange", 0, 0.6, 1, 0, true);
    p.swatches.add (sw);
    assert (p.swatch ("Spot Orange").spot);
    assert (p.unique_swatch_name ("Spot Orange") == "Spot Orange 2");
    assert (!p.is_rgb_color (ColorRef.swatch ("Spot Orange")));
    assert (p.is_rgb_color ("#123456"));
}

void test_rename_swatch () {
    var p = sample ();
    p.swatches.add (new Swatch.cmyk ("Brand", 1, 0.5, 0, 0));
    var s = new ShapeItem (ShapeKind.RECT);
    s.id = p.next_id ();
    s.fill = new Fill.solid (ColorRef.swatch ("Brand", 40));
    p.pages[0].items.add (s);
    assert (p.swatch_in_use ("Brand"));
    p.rename_swatch ("Brand", "Corporate");
    assert (s.fill.color == "swatch:Corporate@40");
    assert (p.swatch ("Corporate") != null && p.swatch ("Brand") == null);
}

void test_pages_sections () {
    var p = Publication.create (null, 6);
    assert (p.pages.size == 6);
    assert (p.page_label (0) == "1" && p.page_label (5) == "6");
    var s = new Section (2);
    s.style = NumberStyle.ROMAN_LOWER;
    s.start_number = 1;
    s.prefix = "A-";
    p.sections.add (s);
    assert (p.page_label (1) == "2");
    assert (p.page_label (2) == "A-i");
    assert (p.page_label (4) == "A-iii");
    s.continue_numbering = true;
    assert (p.page_number (2) == 3);
    var s2 = new Section (4);
    s2.style = NumberStyle.ALPHA_UPPER;
    s2.start_number = 27;
    p.sections.add (s2);
    assert (p.page_label (4) == "AA");
    assert (NumberFormat.roman (1994) == "MCMXCIV");
    assert (NumberFormat.alpha (28) == "AB");
    p.add_page (1, "A");
    assert (p.pages.size == 7);
    assert (s.start_page == 3);
    p.remove_page (3);
    assert (p.pages.size == 6);
    p.move_page (0, 5);
    assert (p.pages.size == 6);
}

void test_spreads () {
    var p = Publication.create (null, 5);
    p.settings.facing = true;
    var sp = p.spreads ();
    assert (sp.size == 3);
    assert (sp[0].pages.size == 1 && !sp[0].first_is_left);
    assert (sp[1].pages.size == 2 && sp[1].first_is_left);
    assert (p.is_left_page (1) && !p.is_left_page (2));
    p.settings.start_left = true;
    sp = p.spreads ();
    assert (sp[0].pages.size == 2);
    p.settings.facing = false;
    assert (p.spreads ().size == 5);
}

void test_margins_bleed () {
    var p = Publication.create (null, 3);
    p.settings.facing = true;
    p.settings.margin_inside = 50;
    p.settings.margin_outside = 20;
    p.settings.set_bleed (9);
    var left = p.margin_rect (1);
    var right = p.margin_rect (2);
    assert (near (left.x, 20) && near (right.x, 50));
    var bl = p.bleed_rect (1);
    assert (near (bl.x, -9) && near (bl.x2 (), p.settings.width));
    var br = p.bleed_rect (2);
    assert (near (br.x, 0) && near (br.x2 (), p.settings.width + 9));
    p.settings.columns = 3;
    p.settings.gutter = 12;
    var cols = p.column_rects (0);
    assert (cols.size == 3);
    assert (near (cols[1].x - cols[0].x2 (), 12));
}

void test_masters () {
    var p = sample ();
    var a = p.master ("A");
    var ta = p.add_text_frame (a.items, 20, 20, 100, 20);
    p.story (ta.story).insert_field (TextPos (0, 0), Fields.PAGE);
    var b = new MasterPage (p.next_master_id (), "Chapter");
    b.based_on = "A";
    p.masters.add (b);
    assert (b.id == "B");
    var rect = new ShapeItem (ShapeKind.RECT);
    rect.id = p.next_id ();
    b.items.add (rect);
    p.pages[1].master = "B";
    var items = p.master_items_for (1);
    assert (items.size == 2);
    assert (p.master_chain ("B").size == 2);
    var ov = p.override_master_item (1, rect);
    assert (ov != null && ov.id != rect.id);
    assert (p.master_items_for (1).size == 1);
    assert (p.pages[1].items.contains (ov));
    p.pages[2].hide_master = true;
    assert (p.master_items_for (2).size == 0);
    b.based_on = "B";
    assert (p.master_chain ("B").size == 1);
}

void test_threading () {
    var p = sample ();
    var f1 = p.add_text_frame (p.pages[0].items, 10, 10, 100, 100);
    var f2 = p.add_text_frame (p.pages[1].items, 10, 10, 100, 100);
    var f3 = p.add_text_frame (p.pages[2].items, 10, 10, 100, 100);
    p.story (f1.story).insert_text (TextPos (0, 0), "First story");
    p.story (f2.story).insert_text (TextPos (0, 0), "Second story");
    int dead = f2.story;
    p.link_frames (f1, f2);
    assert (f2.story == f1.story);
    assert (!p.stories.has_key (dead));
    var s = p.story (f1.story);
    assert (s.plain_text () == "First story\nSecond story");
    p.link_frames (f2, f3);
    var frames = p.thread_frames (f1.story);
    assert (frames.size == 3 && frames[0] == f1 && frames[1] == f2 && frames[2] == f3);
    p.unlink_after (f1);
    assert (p.thread_frames (f1.story).size == 1);
    assert (f2.story == f3.story && f2.story != f1.story);
    p.detach_frame (f3);
    assert (f3.story != f2.story);
    p.pages[1].items.remove (f2);
    p.prune_stories ();
    assert (!p.stories.has_key (f2.story));
}

void test_story_editing () {
    var s = new Story (1);
    var end = s.insert_text (TextPos (0, 0), "Hello world\nSecond line");
    assert (s.paras.size == 2);
    assert (end.para == 1 && end.offset == 11);
    s.apply_chars (TextPos (0, 0), TextPos (0, 5), (r) => r.fmt.bold = 1);
    assert (s.paras[0].runs.size == 2);
    assert (s.format_at (TextPos (0, 2)).fmt.bold == 1);
    s.delete_range (TextPos (0, 5), TextPos (1, 6));
    assert (s.plain_text () == "Hello line");
    var frag = s.copy_range (TextPos (0, 0), TextPos (0, 5));
    assert (frag.plain_text () == "Hello");
    s.insert_story (TextPos (0, 10), frag);
    assert (s.plain_text () == "Hello lineHello");
    assert (s.linear (TextPos (0, 3)) == 3);
    s.split_paragraph (TextPos (0, 6));
    assert (s.from_linear (7).para == 1 && s.from_linear (7).offset == 0);
    TextPos a, b;
    s.word_bounds (TextPos (0, 2), out a, out b);
    assert (a.offset == 0 && b.offset == 5);
    var found = s.find_all ("hello", false, false);
    assert (found.size == 2);
    assert (s.find_all ("hello", true, false).size == 0);
    int n = s.replace_all ("Hello", "Bye", true, true);
    assert (n == 1 && s.plain_text ().has_prefix ("Bye"));
    s.insert_field (TextPos (0, 0), Fields.merge ("Name"));
    assert (s.fields ().contains ("merge:Name"));
}

void test_styles () {
    var st = StyleSheet.standard ();
    var pf = ParaFormat.defaults ();
    var cf = CharFormat.defaults ();
    st.resolve_paragraph ("Heading 2", pf, cf);
    assert (near (cf.size, 16));
    assert (cf.bold == 1);
    assert (pf.keep_next == 1);
    assert (pf.hyphenate == 0);
    assert (st.para_chain ("Heading 2").size == 3);
    assert (st.would_cycle ("Basic Paragraph", "Heading 2"));
    assert (!st.would_cycle ("Heading 2", "Body Text"));
    var em = new CharacterStyle ("Strong Emphasis", "Emphasis");
    em.chars.bold = 1;
    st.character.add (em);
    var c2 = new CharFormat ();
    st.resolve_character ("Strong Emphasis", c2);
    assert (c2.bold == 1 && c2.italic == 1);
    assert (st.unique_paragraph_name ("Body Text") == "Body Text 2");
    var tabs = TabStop.parse (TabStop.serialize (new Gee.ArrayList<TabStop>.wrap ({ new TabStop (100, TabKind.RIGHT, "."), new TabStop (30, TabKind.DECIMAL, "") })));
    assert (tabs.size == 2 && near (tabs[0].pos, 30) && tabs[1].kind == TabKind.RIGHT && tabs[1].leader == ".");
}

void test_undo () {
    var d = new Document (Publication.create (null, 1));
    d.checkpoint ("Add");
    d.pub.add_page (-1, "A");
    d.touch ();
    assert (d.pub.pages.size == 2);
    assert (d.can_undo && d.undo_label == "Add");
    d.undo ();
    assert (d.pub.pages.size == 1);
    assert (d.can_redo);
    d.redo ();
    assert (d.pub.pages.size == 2);
    d.checkpoint ("Typing", "t");
    d.checkpoint ("Typing", "t");
    d.undo ();
    assert (!d.can_undo || d.undo_label != "Typing");
}

void test_items () {
    var p = sample ();
    var s = new ShapeItem (ShapeKind.STAR);
    s.w = 100;
    s.h = 100;
    s.sides = 5;
    assert (s.local_points ().size == 10);
    s.rotation = 90;
    var b = s.bounds ();
    assert (near (b.w, 100, 0.5));
    var t = new TableItem (3, 4);
    t.id = p.next_id ();
    t.w = 200;
    t.h = 90;
    t.init_cells (p);
    assert (t.cells.size == 3 && t.cells[0].size == 4);
    t.insert_row (p, 1);
    assert (t.rows == 4);
    t.insert_col (p, 0);
    assert (t.cols == 5);
    t.cells[0][0].story.insert_text (TextPos (0, 0), "A");
    t.cells[0][1].story.insert_text (TextPos (0, 0), "B");
    t.merge (0, 0, 1, 1);
    assert (t.cells[0][0].row_span == 2 && t.cells[0][0].col_span == 2);
    assert (t.cells[1][1].covered);
    assert (t.cells[0][0].story.plain_text ().contains ("B"));
    t.split (0, 0);
    assert (!t.cells[1][1].covered);
    t.delete_row (0);
    t.delete_col (0);
    assert (t.rows == 3 && t.cols == 4);
    var g = new GroupItem ();
    var a = new ShapeItem (ShapeKind.RECT);
    a.x = 10;
    a.y = 10;
    a.w = 20;
    a.h = 20;
    var c = new ShapeItem (ShapeKind.ELLIPSE);
    c.x = 50;
    c.y = 40;
    c.w = 10;
    c.h = 10;
    g.children.add (a);
    g.children.add (c);
    g.fit_children ();
    assert (near (g.x, 10) && near (g.w, 50) && near (g.h, 40));
    g.move_by (5, 5);
    assert (near (a.x, 15) && near (c.y, 45));
    g.scale_children (g.box (), Rect (g.x, g.y, g.w * 2, g.h * 2));
    assert (near (c.x, 15 + 80));
}

void test_media_prune () {
    var p = sample ();
    uint8[] data = { 1, 2, 3, 4 };
    string k = p.add_media (data, "logo.png");
    assert (k.has_suffix (".png"));
    assert (p.add_media (data, "copy.png") == k);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.media = k;
    p.pages[0].items.add (im);
    p.media["orphan.png"] = new Bytes (data);
    p.prune_media ();
    assert (p.media.has_key (k) && !p.media.has_key ("orphan.png"));
}

void test_bundled_patterns () {
    string dir = Environment.get_variable ("PUBLISH_FIXTURES") ?? "tests/fixtures";
    string path = Path.build_filename (dir, "..", "..", "data", "hyphen", "hyphen.tex");
    try {
        var h = Hyphenator.load_file ("en", path);
        assert (h.pattern_count () > 4000);
        assert (h.hyphenate ("hyphenation") == "hy-phen-ation");
        assert (h.hyphenate ("publication") == "pub-li-ca-tion");
        assert (h.hyphenate ("associate") == "as-so-ciate");
        assert (h.hyphenate ("present") == "present");
    } catch (Error e) {
        error (e.message);
    }
    Hyphenator.search_dirs = { Path.build_filename (dir, "..", "..", "data", "hyphen") };
    Hyphenator.reset_cache ();
    var en = Hyphenator.for_language ("en_GB");
    assert (en != null && en.source.has_suffix ("hyphen.tex"));
    Hyphenator.search_dirs = null;
    Hyphenator.reset_cache ();
}

void test_hyphenator () {
    var h = new Hyphenator ("test");
    foreach (string pat in new string[] { "hy3ph", "he2n", "hena4", "hen5at", "1na", "n2at", "1tio", "2io", "o2n" }) h.add_pattern (pat);
    h.left_min = 2;
    h.right_min = 2;
    assert (h.hyphenate ("hyphenation") == "hy-phen-ation");
    h.add_exception ("ta-ble");
    assert (h.hyphenate ("table", "=") == "ta=ble");
    assert (h.points ("ab").length == 0);
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-hyph-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string f = Path.build_filename (dir, "hyph_xx_XX.dic");
    try {
        FileUtils.set_contents (f, "UTF-8\nLEFTHYPHENMIN 2\nRIGHTHYPHENMIN 2\nhy3ph\nhe2n\nhena4\nhen5at\n1na\nn2at\n1tio\n2io\no2n\n");
    } catch (Error e) {
        assert_not_reached ();
    }
    Hyphenator.search_dirs = { dir };
    Hyphenator.reset_cache ();
    var loaded = Hyphenator.for_language ("xx_XX");
    assert (loaded != null && loaded.pattern_count () == 9);
    assert (loaded.hyphenate ("hyphenation") == "hy-phen-ation");
    assert (Hyphenator.describe ("xx_XX").contains ("hyph_xx_XX.dic"));
    assert (Hyphenator.for_language ("zz") == null);
    assert (Hyphenator.describe ("zz").contains ("No hyphenation dictionary"));
    FileUtils.remove (f);
    DirUtils.remove (dir);
    Hyphenator.search_dirs = null;
    Hyphenator.reset_cache ();
}

void test_preflight () {
    var p = Publication.create (null, 1);
    p.settings.set_bleed (9);
    var f = p.add_text_frame (p.pages[0].items, 40, 40, 60, 20);
    var sb = new StringBuilder ();
    for (int i = 0; i < 40; i++) sb.append ("overflowing words ");
    p.story (f.story).insert_text (TextPos (0, 0), sb.str);
    var r = new ShapeItem (ShapeKind.RECT);
    r.id = p.next_id ();
    r.x = -30;
    r.y = 100;
    r.w = 80;
    r.h = 20;
    p.pages[0].items.add (r);
    var off = new ShapeItem (ShapeKind.RECT);
    off.id = p.next_id ();
    off.x = -500;
    off.y = 10;
    off.w = 20;
    off.h = 20;
    p.pages[0].items.add (off);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.link = "/nonexistent/picture.jpg";
    im.w = 50;
    im.h = 50;
    p.pages[0].items.add (im);
    var rgb = new Swatch.rgb ("Screen Blue", 0, 0, 1);
    p.swatches.add (rgb);
    var s2 = new ShapeItem (ShapeKind.RECT);
    s2.id = p.next_id ();
    s2.x = 100;
    s2.y = 100;
    s2.w = 10;
    s2.h = 10;
    s2.fill = new Fill.solid (ColorRef.swatch ("Screen Blue"));
    p.pages[0].items.add (s2);
    var pf = new Preflight (p);
    pf.font_check = (fam) => fam != "Nonexistent Sans";
    var ps = new ParagraphStyle ("Odd", StyleSheet.BASIC);
    ps.chars.font = "Nonexistent Sans";
    p.styles.paragraph.add (ps);
    pf.run ();
    bool overset = false, bleed = false, offp = false, missing = false, rgbc = false, font = false;
    foreach (var i in pf.issues) {
        if (i.kind == IssueKind.OVERSET) overset = true;
        if (i.kind == IssueKind.OUTSIDE_BLEED && i.item == r.id) bleed = true;
        if (i.kind == IssueKind.OFF_PAGE && i.item == off.id) offp = true;
        if (i.kind == IssueKind.MISSING_LINK) missing = true;
        if (i.kind == IssueKind.RGB_COLOR) rgbc = true;
        if (i.kind == IssueKind.MISSING_FONT && i.message.contains ("Nonexistent Sans")) font = true;
    }
    assert (overset && bleed && offp && missing && rgbc && font);
    assert (pf.count (Severity.ERROR) >= 3);
}

void test_low_res_and_rgb_image () {
    var p = Publication.create (null, 1);
    var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 40, 30);
    pb.fill ((uint32) 0x3366ccff);
    uint8[] png;
    try {
        pb.save_to_buffer (out png, "png");
    } catch (Error e) {
        assert_not_reached ();
    }
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.media = p.add_media (png, "small.png");
    im.w = 200;
    im.h = 150;
    p.pages[0].items.add (im);
    var pf = new Preflight (p);
    pf.font_check = (f) => true;
    pf.run ();
    bool low = false, rgb = false;
    foreach (var i in pf.issues) {
        if (i.kind == IssueKind.LOW_RES && i.severity == Severity.ERROR) low = true;
        if (i.kind == IssueKind.RGB_IMAGE) rgb = true;
    }
    assert (low && rgb);
    var inf = ImageStore.decode (png);
    var pl = ImageStore.place (im, inf);
    assert (near (pl.ppi_x (), 72.0 * 40 / 200, 0.5));
    im.fit = FitMode.FIT;
    pl = ImageStore.place (im, inf);
    assert (near (pl.sx, 5) && near (pl.oy, 0));
    ImageStore.to_manual (im, inf);
    assert (im.fit == FitMode.MANUAL);
    var pl2 = ImageStore.place (im, inf);
    assert (near (pl2.sx, pl.sx) && near (pl2.ox, pl.ox));
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/model/units", test_units);
    Test.add_func ("/model/colors", test_colors);
    Test.add_func ("/model/rename-swatch", test_rename_swatch);
    Test.add_func ("/model/pages-sections", test_pages_sections);
    Test.add_func ("/model/spreads", test_spreads);
    Test.add_func ("/model/margins-bleed", test_margins_bleed);
    Test.add_func ("/model/masters", test_masters);
    Test.add_func ("/model/threading", test_threading);
    Test.add_func ("/model/story-editing", test_story_editing);
    Test.add_func ("/model/styles", test_styles);
    Test.add_func ("/model/undo", test_undo);
    Test.add_func ("/model/items", test_items);
    Test.add_func ("/model/media-prune", test_media_prune);
    Test.add_func ("/model/hyphenator", test_hyphenator);
    Test.add_func ("/model/bundled-patterns", test_bundled_patterns);
    Test.add_func ("/model/preflight", test_preflight);
    Test.add_func ("/model/low-res-rgb", test_low_res_and_rgb_image);
    return Test.run ();
}
