using Singularity.Apps.Publish;

bool near (double a, double b, double eps = 0.01) {
    return (a - b).abs () <= eps;
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

Publication base_pub () {
    var p = Publication.create (null, 2);
    var body = p.styles.find_paragraph ("Body Text");
    body.para.align = (int) TextAlign.LEFT;
    body.para.hyphenate = 0;
    p.styles.find_paragraph (StyleSheet.BASIC).para.hyphenate = 0;
    p.styles.find_paragraph (StyleSheet.BASIC).chars.font = "DejaVu Sans";
    return p;
}

TextFrame frame (Publication p, int page, double x, double y, double w, double h, Story? s = null) {
    return p.add_text_frame (p.pages[page].items, x, y, w, h, s);
}

void fill (Publication p, TextFrame f, int paras, int words, string style = "Body Text") {
    var s = p.story (f.story);
    s.paras.clear ();
    for (int i = 0; i < paras; i++) s.paras.add (new Paragraph.with_text (lorem (words), style));
}

int total_lines (FrameResult fr) {
    int n = 0;
    foreach (var l in fr.lines) if (!l.is_drop) n++;
    return n;
}

void test_threading_overflow () {
    var p = base_pub ();
    var f1 = frame (p, 0, 50, 50, 200, 100);
    fill (p, f1, 12, 40);
    var f2 = frame (p, 1, 50, 50, 200, 100);
    var cache = new LayoutCache (p);
    var r = cache.story (f1.story);
    assert (r.overset);
    int before = r.overset_chars;
    p.link_frames (f1, f2);
    cache.invalidate ();
    r = cache.story (f1.story);
    assert (r.frames.size == 2);
    assert (total_lines (r.frames[0]) > 3 && total_lines (r.frames[1]) > 3);
    assert (r.overset && r.overset_chars < before);
    assert (r.frames[1].first.compare (r.frames[0].last) >= 0);
    f2.h = 2000;
    cache.invalidate ();
    r = cache.story (f1.story);
    assert (!r.overset);
    foreach (var l in r.frames[0].lines) assert (l.baseline + l.descent <= 100.5);
    int linear_end = 0;
    foreach (var fr in r.frames) foreach (var l in fr.lines) {
        int e = p.story (f1.story).linear (TextPos (l.para, l.end));
        assert (e >= linear_end - 1);
        linear_end = int.max (linear_end, e);
    }
    assert (linear_end == p.story (f1.story).char_count ());
}

void test_columns () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 312, 200);
    f.columns = 3;
    f.gutter = 12;
    fill (p, f, 10, 30);
    var r = new LayoutCache (p).story (f.story);
    var fr = r.frames[0];
    int[] counts = new int[3];
    foreach (var l in fr.lines) {
        counts[l.column]++;
        double col_x = l.column * (96 + 12);
        assert (l.x >= col_x - 0.01);
        assert (l.x + l.width <= col_x + 96 + 0.01);
    }
    assert (counts[0] > 0 && counts[1] > 0 && counts[2] > 0);
}

void test_wrap_box_and_sides () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 300);
    fill (p, f, 6, 60);
    var box = new ShapeItem (ShapeKind.RECT);
    box.id = p.next_id ();
    box.x = 100;
    box.y = 50;
    box.w = 100;
    box.h = 100;
    box.wrap = WrapMode.BOUNDING_BOX;
    box.wrap_offset = 5;
    p.pages[0].items.add (box);
    var cache = new LayoutCache (p);
    var fr = cache.story (f.story).frames[0];
    bool left = false, right = false;
    foreach (var l in fr.lines) {
        double top = l.baseline - l.ascent, bot = l.baseline + l.descent;
        if (bot > 45 && top < 155) {
            assert (l.x + l.width <= 95.01 || l.x >= 204.99);
            if (l.x < 95) left = true;
            if (l.x >= 204.99) right = true;
        }
    }
    assert (left && right);
    box.wrap_side = WrapSide.LEFT;
    cache.invalidate ();
    fr = cache.story (f.story).frames[0];
    foreach (var l in fr.lines) {
        double top = l.baseline - l.ascent, bot = l.baseline + l.descent;
        if (bot > 45 && top < 155) assert (l.x + l.width <= 95.01);
    }
    box.wrap = WrapMode.JUMP;
    cache.invalidate ();
    fr = cache.story (f.story).frames[0];
    foreach (var l in fr.lines) {
        double top = l.baseline - l.ascent, bot = l.baseline + l.descent;
        assert (bot <= 45.01 || top >= 154.99);
    }
    f.ignore_wrap = true;
    cache.invalidate ();
    fr = cache.story (f.story).frames[0];
    bool through = false;
    foreach (var l in fr.lines) if (l.baseline > 60 && l.baseline < 140 && l.x < 100 && l.x + l.width > 200) through = true;
    assert (through);
}

void test_wrap_contour () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 300);
    fill (p, f, 6, 60);
    var e = new ShapeItem (ShapeKind.ELLIPSE);
    e.id = p.next_id ();
    e.x = 100;
    e.y = 100;
    e.w = 100;
    e.h = 100;
    e.wrap = WrapMode.CONTOUR;
    e.wrap_offset = 0;
    e.wrap_side = WrapSide.LEFT;
    p.pages[0].items.add (e);
    var fr = new LayoutCache (p).story (f.story).frames[0];
    double near_top = -1, middle = -1;
    foreach (var l in fr.lines) {
        double mid = l.baseline - l.ascent / 2;
        if (mid > 102 && mid < 118 && near_top < 0) near_top = l.x + l.width;
        if (mid > 142 && mid < 158) middle = l.x + l.width;
    }
    assert (near_top > 0 && middle > 0);
    assert (middle < near_top);
    assert (middle <= 100.5);
}

void test_drop_cap () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 400);
    fill (p, f, 1, 80);
    var para = p.story (f.story).paras[0];
    para.fmt.drop_lines = 3;
    para.fmt.drop_chars = 1;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    LaidLine? drop = null;
    var lines = new Gee.ArrayList<LaidLine> ();
    foreach (var l in fr.lines) {
        if (l.is_drop) drop = l;
        else lines.add (l);
    }
    assert (drop != null);
    assert (drop.start == 0 && drop.end == 1);
    assert (lines[0].start == 1);
    assert (lines[0].x > drop.x + 5);
    assert (lines[2].x > drop.x + 5);
    assert (near (lines[3].x, 0, 0.5));
    assert (near (drop.baseline, lines[2].baseline, 0.5));
}

void test_tabs_leaders () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 100);
    var s = p.story (f.story);
    s.paras.clear ();
    var para = new Paragraph.with_text ("Soup\t4.50");
    para.fmt.tabs = TabStop.serialize (new Gee.ArrayList<TabStop>.wrap ({ new TabStop (250, TabKind.RIGHT, ".") }));
    s.paras.add (para);
    var fr = new LayoutCache (p).story (f.story).frames[0];
    var l = fr.lines[0];
    assert (l.leaders.size == 1);
    assert (l.leaders[0].text == ".");
    assert (l.leaders[0].x1 > 150);
    int w, h;
    var layout = l.layout;
    layout.get_pixel_size (out w, out h);
    double end_x = l.caret_x (9);
    assert (near (end_x, 250, 2));
}

void test_lists () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 300);
    var s = p.story (f.story);
    s.paras.clear ();
    for (int i = 0; i < 3; i++) s.paras.add (new Paragraph.with_text ("Item %d".printf (i + 1), "Numbered List"));
    s.paras.add (new Paragraph.with_text ("Break"));
    s.paras.add (new Paragraph.with_text ("Again", "Numbered List"));
    var b = new Paragraph.with_text ("Bullet", "Bulleted List");
    s.paras.add (b);
    var c = new Paragraph.with_text ("Roman", "Numbered List");
    c.fmt.number_format = 4;
    c.fmt.number_start = 4;
    s.paras.add (c);
    var fr = new LayoutCache (p).story (f.story).frames[0];
    var texts = new Gee.ArrayList<string> ();
    foreach (var l in fr.lines) texts.add (l.build.text);
    assert (texts[0].has_prefix ("1.\t"));
    assert (texts[2].has_prefix ("3.\t"));
    assert (texts[4].has_prefix ("1.\t"));
    assert (texts[5].has_prefix ("•\t"));
    assert (texts[6].has_prefix ("iv.\t"));
    var l0 = fr.lines[0];
    assert (l0.caret_x (0) > 5);
    assert (l0.hit (l0.caret_x (0) + 0.1) == 0);
}

void test_baseline_grid () {
    var p = base_pub ();
    p.settings.baseline_start = 36;
    p.settings.baseline_step = 15;
    var f = frame (p, 0, 20, 40, 300, 300);
    fill (p, f, 3, 30);
    foreach (var para in p.story (f.story).paras) para.fmt.align_grid = 1;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    foreach (var l in fr.lines) {
        double page_y = f.y + l.baseline;
        double k = (page_y - 36) / 15;
        assert (near (k, Math.round (k), 0.001));
    }
}

void test_justify () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 200, 400);
    fill (p, f, 1, 60);
    p.story (f.story).paras[0].fmt.align = (int) TextAlign.JUSTIFY;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    int full = 0;
    for (int i = 0; i < fr.lines.size - 1; i++) {
        var l = fr.lines[i];
        Pango.Rectangle ink, log;
        l.line ().get_extents (out ink, out log);
        if (near (log.width / (double) Pango.SCALE, 200, 1.5)) full++;
    }
    assert (full >= fr.lines.size - 2);
    var last = fr.lines[fr.lines.size - 1];
    Pango.Rectangle ink2, log2;
    last.line ().get_extents (out ink2, out log2);
    assert (log2.width / (double) Pango.SCALE < 199);
}

void test_hyphenation_in_layout () {
    var p = base_pub ();
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-lhyph-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (dir, "hyph_en_US.dic"), "UTF-8\nLEFTHYPHENMIN 2\nRIGHTHYPHENMIN 2\nhy3ph\nhe2n\nhena4\nhen5at\n1na\nn2at\n1tio\n2io\no2n\n");
    } catch (Error e) {
        assert_not_reached ();
    }
    Hyphenator.search_dirs = { dir };
    Hyphenator.reset_cache ();
    var f = frame (p, 0, 0, 0, 300, 300);
    var s = p.story (f.story);
    s.paras.clear ();
    var para = new Paragraph.with_text ("hyphenation hyphenation hyphenation");
    para.fmt.hyphenate = 1;
    s.paras.add (para);
    var fr = new LayoutCache (p).story (f.story).frames[0];
    assert (fr.lines[0].build.text.contains ("\u00AD"));
    assert (fr.lines[0].build.story_of (fr.lines[0].build.disp_of (11)) == 11);
    para.fmt.hyphenate = 0;
    fr = new LayoutCache (p).story (f.story).frames[0];
    assert (!fr.lines[0].build.text.contains ("\u00AD"));
    FileUtils.remove (Path.build_filename (dir, "hyph_en_US.dic"));
    DirUtils.remove (dir);
    Hyphenator.search_dirs = null;
    Hyphenator.reset_cache ();
}

void test_fields_on_master () {
    var p = base_pub ();
    p.add_page (-1, "A");
    var m = p.master ("A");
    var f = p.add_text_frame (m.items, 20, 800, 100, 20);
    var s = p.story (f.story);
    s.insert_text (TextPos (0, 0), "Page ");
    s.insert_field (TextPos (0, 5), Fields.PAGE);
    s.insert_text (TextPos (0, 6), " of ");
    s.insert_field (TextPos (0, 10), Fields.PAGES);
    var cache = new LayoutCache (p);
    var r0 = cache.master_story (f.story, 0);
    var r2 = cache.master_story (f.story, 2);
    assert (r0.frames[0].lines[0].build.text == "Page 1 of 3");
    assert (r2.frames[0].lines[0].build.text == "Page 3 of 3");
    var sec = new Section (1);
    sec.style = NumberStyle.ROMAN_UPPER;
    sec.start_number = 5;
    p.sections.add (sec);
    cache.invalidate ();
    assert (cache.master_story (f.story, 2).frames[0].lines[0].build.text == "Page VI of 3");
    var lb = cache.master_story (f.story, 0).frames[0].lines[0].build;
    assert (lb.story_of (lb.disp_of (6)) == 6);
}

void test_jump_lines () {
    var p = base_pub ();
    var f1 = frame (p, 0, 0, 0, 200, 60);
    fill (p, f1, 4, 40);
    var f2 = frame (p, 1, 0, 0, 200, 600);
    p.link_frames (f1, f2);
    var note = frame (p, 0, 0, 70, 200, 20);
    var ns = p.story (note.story);
    ns.insert_text (TextPos (0, 0), "Continued on page ");
    ns.insert_field (TextPos (0, 18), Fields.NEXT_PAGE);
    var r = new LayoutCache (p).story (note.story);
    assert (r.frames[0].lines[0].build.text.has_prefix ("Continued on page #"));
    var fc = new FieldContext (p);
    fc.next_page = 1;
    assert (fc.resolve (Fields.NEXT_PAGE) == "2");
}

void test_valign () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 200, 400);
    fill (p, f, 1, 5);
    f.valign = 2;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    var l = fr.lines[fr.lines.size - 1];
    assert (near (l.baseline + l.descent, 400, 0.6));
    f.valign = 1;
    fr = new LayoutCache (p).story (f.story).frames[0];
    l = fr.lines[0];
    assert (l.baseline > 150 && l.baseline < 250);
}

void test_keep_with_next () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 200, 60);
    f.columns = 2;
    f.w = 412;
    var s = p.story (f.story);
    s.paras.clear ();
    s.paras.add (new Paragraph.with_text ("one two three"));
    s.paras.add (new Paragraph.with_text ("two"));
    s.paras.add (new Paragraph.with_text ("A Heading", "Heading 2"));
    s.paras.add (new Paragraph.with_text (lorem (60)));
    var fr = new LayoutCache (p).story (f.story).frames[0];
    int head_col = -1, body_col = -1;
    foreach (var l in fr.lines) {
        if (l.para == 2 && head_col < 0) head_col = l.column;
        if (l.para == 3 && body_col < 0) body_col = l.column;
    }
    assert (head_col == body_col);
}

void test_hit_and_caret () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 100);
    var s = p.story (f.story);
    s.paras.clear ();
    s.paras.add (new Paragraph.with_text ("Hello brave new world"));
    var fr = new LayoutCache (p).story (f.story).frames[0];
    var l = fr.lines[0];
    for (int i = 0; i <= 21; i++) {
        double x = l.caret_x (i);
        assert (l.hit (x + 0.01) == i || l.hit (x - 0.01) == i);
    }
    assert (l.caret_x (5) > l.caret_x (0));
    assert (l.hit (-100) == 0);
    assert (l.hit (1000) == 21);
}

void test_empty_and_small () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 100, 100);
    var r = new LayoutCache (p).story (f.story);
    assert (!r.overset);
    assert (r.frames[0].lines.size == 1);
    var tiny = frame (p, 0, 0, 200, 100, 2);
    p.story (tiny.story).insert_text (TextPos (0, 0), "Too small");
    var r2 = new LayoutCache (p).story (tiny.story);
    assert (r2.overset);
    assert (r2.overset_chars == 9);
}

void test_char_formats () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 300, 100);
    var s = p.story (f.story);
    s.paras.clear ();
    s.paras.add (new Paragraph.with_text ("Normal Bold Super"));
    s.apply_chars (TextPos (0, 7), TextPos (0, 11), (r) => {
        r.fmt.bold = 1;
        r.fmt.tracking = 200;
        r.fmt.color = ColorRef.swatch ("Red");
    });
    s.apply_chars (TextPos (0, 12), TextPos (0, 17), (r) => r.fmt.position = 1);
    s.apply_chars (TextPos (0, 0), TextPos (0, 6), (r) => {
        r.fmt.caps = 1;
        r.fmt.features = "smcp=1";
        r.fmt.kerning = 0;
    });
    var e = new TextEngine (p);
    var fr = e.layout_story (f.story).frames[0];
    var b = fr.lines[0].build;
    assert (b.spans.size == 5 || b.spans.size == 4);
    var attrs = e.attrs_for (b, 0, b.text.length);
    var it = attrs.get_iterator ();
    bool found_rise = false, found_spacing = false, found_features = false;
    do {
        foreach (unowned Pango.Attribute a in it.get_attrs ()) {
            if (a.klass.type == Pango.AttrType.RISE) found_rise = true;
            if (a.klass.type == Pango.AttrType.LETTER_SPACING) found_spacing = true;
            if (a.klass.type == Pango.AttrType.FONT_FEATURES) found_features = true;
        }
    } while (it.next ());
    assert (found_rise && found_spacing && found_features);
    double x_bold = fr.lines[0].caret_x (11) - fr.lines[0].caret_x (7);
    s.apply_chars (TextPos (0, 7), TextPos (0, 11), (r) => r.fmt.tracking = 0);
    fr = new TextEngine (p).layout_story (f.story).frames[0];
    assert (fr.lines[0].caret_x (11) - fr.lines[0].caret_x (7) < x_bold);
}

void test_cells () {
    var p = base_pub ();
    var s = new Story (99);
    s.insert_text (TextPos (0, 0), lorem (30));
    var e = new TextEngine (p);
    var fr = e.layout_box (s, 80, 100000);
    assert (fr.lines.size > 2);
    assert (fr.content_height > 30);
    foreach (var l in fr.lines) assert (l.x + l.width <= 80.01);
}

void test_paragraph_composer () {
    var fm = Pango.CairoFontMap.new ();
    ((Pango.CairoFontMap) fm).set_resolution (72);
    var ctx = fm.create_context ();
    var l = new Pango.Layout (ctx);
    l.set_font_description (Pango.FontDescription.from_string ("DejaVu Sans 10"));
    var sb = new StringBuilder ();
    for (int i = 0; i < 4; i++) sb.append ("Typesetting a long paragraph well means balancing the spaces of every line against its neighbours, so no single line is left loose or tight. ");
    l.set_text (sb.str.strip (), -1);
    l.set_width (-1);
    var pf = ParaFormat.defaults ();
    var comp = new ParagraphComposer (pf);
    assert (comp.prepare (l, 0));
    var kp = comp.compose ((n) => 190, true, false);
    var gr = comp.greedy ((n) => 190, true);
    assert (kp != null && kp.size > 3);
    double kp_worst = 0, gr_worst = 0, kp_sum = 0, gr_sum = 0;
    for (int i = 0; i < kp.size - 1; i++) {
        kp_worst = double.max (kp_worst, Math.fabs (kp[i].ratio));
        kp_sum += Math.pow (10 + 100 * Math.pow (Math.fabs (kp[i].ratio), 3), 2);
    }
    for (int i = 0; i < gr.size - 1; i++) {
        gr_worst = double.max (gr_worst, Math.fabs (gr[i].ratio));
        gr_sum += Math.pow (10 + 100 * Math.pow (Math.fabs (gr[i].ratio), 3), 2);
    }
    assert (kp_worst <= gr_worst + 1e-6);
    assert (kp_sum <= gr_sum + 100 * kp.size);
    int prev = 0;
    foreach (var line in kp) {
        assert (line.start == prev || line.start > prev);
        assert (line.end >= line.start);
        prev = line.next;
    }
    assert (prev == sb.str.strip ().length);
    var single = ParaFormat.defaults ();
    single.composer = 1;
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 190, 600);
    fill (p, f, 1, 80);
    p.story (f.story).paras[0].fmt.align = (int) TextAlign.JUSTIFY;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    foreach (var ll in fr.lines) assert (ll.composed);
    p.story (f.story).paras[0].fmt.composer = 1;
    var fr2 = new LayoutCache (p).story (f.story).frames[0];
    foreach (var ll in fr2.lines) assert (!ll.composed);
}

void test_justification_limits () {
    var p = base_pub ();
    var f = frame (p, 0, 0, 0, 180, 600);
    fill (p, f, 1, 70);
    var para = p.story (f.story).paras[0];
    para.fmt.align = (int) TextAlign.JUSTIFY;
    para.fmt.letter_min = -5;
    para.fmt.letter_max = 10;
    para.fmt.glyph_min = 97;
    para.fmt.glyph_max = 103;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    bool scaled = false;
    for (int i = 0; i < fr.lines.size - 1; i++) {
        var l = fr.lines[i];
        Pango.Rectangle ink, log;
        l.line ().get_extents (out ink, out log);
        double drawn = log.width / (double) Pango.SCALE * l.hscale;
        assert (near (drawn, 180, 1.0));
        assert (l.hscale >= 0.97 - 1e-6 && l.hscale <= 1.03 + 1e-6);
        if (Math.fabs (l.hscale - 1) > 1e-4) scaled = true;
    }
    assert (scaled);
    try {
        var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
        var qp = q.story (f.story).paras[0];
        assert (qp.fmt.glyph_max == 103 && qp.fmt.letter_min == -5);
    } catch (Error e) {
        error (e.message);
    }
}

string hyph_marks (string text) {
    return text.replace ("\u00AD", "-");
}

void test_hyphenation_settings () {
    var p = base_pub ();
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-lhyph2-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    try {
        FileUtils.set_contents (Path.build_filename (dir, "hyph_en_US.dic"), "UTF-8\nLEFTHYPHENMIN 2\nRIGHTHYPHENMIN 2\nhy3ph\nhe2n\nhena4\nhen5at\n1na\nn2at\n1tio\n2io\no2n\n");
    } catch (Error e) {
        assert_not_reached ();
    }
    Hyphenator.search_dirs = { dir };
    Hyphenator.reset_cache ();
    var f = frame (p, 0, 0, 0, 300, 300);
    var s = p.story (f.story);
    s.paras.clear ();
    var para = new Paragraph.with_text ("hyphenation Hyphenation typesetting");
    para.fmt.hyphenate = 1;
    s.paras.add (para);
    var t0 = hyph_marks (new LayoutCache (p).story (f.story).frames[0].lines[0].build.text);
    assert (t0.contains ("hy-phen-ation") && t0.contains ("Hy-phen-ation"));
    para.fmt.hyph_caps = 0;
    var t1 = hyph_marks (new LayoutCache (p).story (f.story).frames[0].lines[0].build.text);
    assert (t1.contains ("hy-phen-ation") && t1.contains ("Hyphenation "));
    para.fmt.hyph_before = 3;
    var t2 = hyph_marks (new LayoutCache (p).story (f.story).frames[0].lines[0].build.text);
    assert (t2.contains ("hyphen-ation") && !t2.contains ("hy-"));
    para.fmt.hyph_min_word = 20;
    var t3 = hyph_marks (new LayoutCache (p).story (f.story).frames[0].lines[0].build.text);
    assert (!t3.contains ("-"));
    para.fmt.hyph_min_word = 5;
    p.hyph_exceptions["typesetting"] = "type-set-ting";
    p.hyph_exceptions["hyphenation"] = "hyphenation";
    var t4 = hyph_marks (new LayoutCache (p).story (f.story).frames[0].lines[0].build.text);
    assert (t4.contains ("type-set-ting") && t4.has_prefix ("hyphenation "));
    try {
        var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
        assert (q.hyph_exceptions["typesetting"] == "type-set-ting" && q.hyph_exceptions.size == 2);
    } catch (Error e) {
        error (e.message);
    }
    FileUtils.remove (Path.build_filename (dir, "hyph_en_US.dic"));
    DirUtils.remove (dir);
    Hyphenator.search_dirs = null;
    Hyphenator.reset_cache ();
}

void test_text_variables () {
    var p = base_pub ();
    var m = p.master ("A");
    var head = new TextVariable ("Head", "running");
    head.style = "Heading 1";
    p.text_vars.add (head);
    var last = new TextVariable ("LastHead", "running");
    last.style = "Heading 1";
    last.use_last = true;
    p.text_vars.add (last);
    var custom = new TextVariable ("Edition", "custom");
    custom.text = "Autumn";
    custom.before = "[";
    custom.after = "]";
    p.text_vars.add (custom);
    p.text_vars.add (new TextVariable ("Chap", "chapter"));
    p.chapter_number = 4;
    p.file_name = "guide.spub";
    p.text_vars.add (new TextVariable ("File", "file"));
    var mf = p.add_text_frame (m.items, 20, 10, 400, 20);
    var ms = p.story (mf.story);
    ms.insert_field (TextPos (0, 0), Fields.variable ("Head"));
    ms.insert_text (TextPos (0, 1), " / ");
    ms.insert_field (TextPos (0, 4), Fields.variable ("LastHead"));
    ms.insert_text (TextPos (0, 5), " ");
    ms.insert_field (TextPos (0, 6), Fields.variable ("Edition"));
    ms.insert_text (TextPos (0, 7), " ");
    ms.insert_field (TextPos (0, 8), Fields.variable ("Chap"));
    ms.insert_text (TextPos (0, 9), " ");
    ms.insert_field (TextPos (0, 10), Fields.variable ("File"));
    for (int pg = 0; pg < 2; pg++) {
        var f = frame (p, pg, 20, 60, 400, 600);
        var st = p.story (f.story);
        st.paras.clear ();
        st.paras.add (new Paragraph.with_text (pg == 0 ? "Harbours" : "Lighthouses", "Heading 1"));
        st.paras.add (new Paragraph.with_text ("Some body text.", "Body Text"));
        st.paras.add (new Paragraph.with_text (pg == 0 ? "Boats" : "Keepers", "Heading 1"));
    }
    var cache = new LayoutCache (p);
    assert (cache.master_story (mf.story, 0).frames[0].lines[0].build.text == "Harbours / Boats [Autumn] 4 guide.spub");
    assert (cache.master_story (mf.story, 1).frames[0].lines[0].build.text == "Lighthouses / Keepers [Autumn] 4 guide.spub");
    try {
        var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
        assert (q.text_vars.size == 5 && q.chapter_number == 4 && q.text_var ("LastHead").use_last && q.text_var ("Edition").before == "[");
    } catch (Error e) {
        error (e.message);
    }
}

void test_frame_grid () {
    var p = base_pub ();
    var f = frame (p, 0, 30, 47, 300, 400);
    fill (p, f, 2, 30);
    foreach (var para in p.story (f.story).paras) para.fmt.align_grid = 1;
    f.own_grid = true;
    f.grid_start = 10;
    f.grid_step = 20;
    var fr = new LayoutCache (p).story (f.story).frames[0];
    assert (fr.lines.size > 3);
    foreach (var l in fr.lines) {
        double k = (l.baseline - 10) / 20;
        assert (Math.fabs (k - Math.round (k)) < 1e-6);
    }
    f.rotation = 15;
    var fr2 = new LayoutCache (p).story (f.story).frames[0];
    foreach (var l in fr2.lines) assert (Math.fabs ((l.baseline - 10) / 20 - Math.round ((l.baseline - 10) / 20)) < 1e-6);
    try {
        var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
        var qf = (TextFrame) q.find_item (f.id).item;
        assert (qf.own_grid && qf.grid_step == 20 && qf.grid_start == 10);
    } catch (Error e) {
        error (e.message);
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/layout/threading", test_threading_overflow);
    Test.add_func ("/layout/columns", test_columns);
    Test.add_func ("/layout/wrap-box", test_wrap_box_and_sides);
    Test.add_func ("/layout/wrap-contour", test_wrap_contour);
    Test.add_func ("/layout/drop-cap", test_drop_cap);
    Test.add_func ("/layout/tabs-leaders", test_tabs_leaders);
    Test.add_func ("/layout/lists", test_lists);
    Test.add_func ("/layout/baseline-grid", test_baseline_grid);
    Test.add_func ("/layout/justify", test_justify);
    Test.add_func ("/layout/paragraph-composer", test_paragraph_composer);
    Test.add_func ("/layout/justification-limits", test_justification_limits);
    Test.add_func ("/layout/hyphenation-settings", test_hyphenation_settings);
    Test.add_func ("/layout/text-variables", test_text_variables);
    Test.add_func ("/layout/frame-grid", test_frame_grid);
    Test.add_func ("/layout/hyphenation", test_hyphenation_in_layout);
    Test.add_func ("/layout/master-fields", test_fields_on_master);
    Test.add_func ("/layout/jump-lines", test_jump_lines);
    Test.add_func ("/layout/valign", test_valign);
    Test.add_func ("/layout/keep-with-next", test_keep_with_next);
    Test.add_func ("/layout/hit-caret", test_hit_and_caret);
    Test.add_func ("/layout/empty-small", test_empty_and_small);
    Test.add_func ("/layout/char-formats", test_char_formats);
    Test.add_func ("/layout/cells", test_cells);
    return Test.run ();
}
