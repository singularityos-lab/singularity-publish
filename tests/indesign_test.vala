using Singularity.Apps.Publish;

Publication doc () {
    var p = Publication.create (null, 2);
    p.styles.find_paragraph (StyleSheet.BASIC).chars.font = "DejaVu Sans";
    return p;
}

Publication round_trip (Publication p) {
    try {
        return NativeFormat.from_xml (NativeFormat.to_xml (p));
    } catch (Error e) {
        error (e.message);
    }
}

void test_style_groups () {
    var p = doc ();
    var h = p.styles.find_paragraph ("Heading 1");
    h.group = "Headings";
    p.styles.find_character ("Strong").group = "Emphasis";
    var q = round_trip (p);
    assert (q.styles.find_paragraph ("Heading 1").group == "Headings");
    assert (q.styles.find_character ("Strong").group == "Emphasis");
    assert (q.styles.find_paragraph (StyleSheet.BASIC).group == "");
}

void test_object_styles () {
    var p = doc ();
    var src = p.add_text_frame (p.pages[0].items, 20, 20, 200, 100);
    src.fill = new Fill.solid ("#ffcc00");
    src.stroke = new Stroke.with ("#003366", 2);
    src.corner = CornerKind.ROUNDED;
    src.corner_radius = 8;
    src.wrap = WrapMode.BOUNDING_BOX;
    src.wrap_offset = 9;
    src.inset_left = 12;
    src.columns = 2;
    src.effects.glow = true;
    p.story (src.story).paras[0].style = "Heading 2";
    var os = ObjectStyle.from_item ("Callout", src, p);
    os.use_para = true;
    p.object_styles.add (os);
    var box = new ObjectStyle ("Plain Box");
    box.use_fill = false;
    box.use_stroke = true;
    box.use_effects = false;
    box.use_corner = false;
    box.use_wrap = false;
    box.use_frame = false;
    box.proto.stroke = new Stroke.with ("#ff0000", 4);
    box.based_on = "Callout";
    p.object_styles.add (box);
    var t = p.add_text_frame (p.pages[1].items, 10, 10, 150, 80);
    os.apply_to (p, t);
    assert (t.object_style == "Callout");
    assert (t.fill.color == "#ffcc00" && t.stroke.width == 2 && t.corner == CornerKind.ROUNDED && t.corner_radius == 8);
    assert (t.wrap == WrapMode.BOUNDING_BOX && t.wrap_offset == 9 && t.inset_left == 12 && t.columns == 2 && t.effects.glow);
    assert (p.story (t.story).paras[0].style == "Heading 2");
    assert (t.x == 10 && t.w == 150);
    var shape = new ShapeItem (ShapeKind.ELLIPSE);
    shape.id = p.next_id ();
    shape.fill = new Fill.solid ("#00ff00");
    p.pages[1].items.add (shape);
    box.apply_to (p, shape);
    assert (shape.fill.color == "#ffcc00");
    assert (shape.stroke.color == "#ff0000" && shape.stroke.width == 4);
    assert (shape.object_style == "Plain Box");
    var q = round_trip (p);
    assert (q.object_styles.size == 2);
    var qos = q.object_style ("Callout");
    assert (qos.use_para && qos.para_style == "Heading 2" && qos.proto.columns == 2 && qos.proto.fill.color == "#ffcc00");
    assert (q.object_style ("Plain Box").based_on == "Callout" && !q.object_style ("Plain Box").use_fill);
    assert (q.find_item (t.id).item.object_style == "Callout");
}

void test_grep_find_replace () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 300, 200);
    var st = p.story (t.story);
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text ("Call 555-0142 or 555-0199 today.", "Body Text"));
    var p2 = new Paragraph.with_text ("Prices: 12 EUR, 7 EUR.", "Heading 2");
    st.paras.add (p2);
    var q = new FindQuery ();
    q.grep = true;
    q.pattern = "(\\d{3})-(\\d{4})";
    try {
        var found = Finder.search (p, st, q);
        assert (found.size == 2);
        assert (found[0].a.offset == 5 && found[0].b.offset == 13 && found[0].groups[2] == "0142");
        q.replacement = "($1) $2";
        assert (Finder.replace_all (p, new Gee.ArrayList<Story>.wrap ({ st }), q) == 2);
        assert (st.paras[0].text () == "Call (555) 0142 or (555) 0199 today.");
        var fmt = new FindQuery ();
        fmt.grep = true;
        fmt.pattern = "\\d+ EUR";
        fmt.change_text = false;
        fmt.change_fmt.bold = 1;
        fmt.change_fmt.char_style = "Strong";
        assert (Finder.replace_all (p, new Gee.ArrayList<Story>.wrap ({ st }), fmt) == 2);
        assert (st.paras[1].text () == "Prices: 12 EUR, 7 EUR.");
        bool bold_run = false;
        foreach (var r in st.paras[1].runs) if (r.text == "12 EUR" && r.fmt.bold == 1 && r.cstyle == "Strong") bold_run = true;
        assert (bold_run);
        var bystyle = new FindQuery ();
        bystyle.pattern = "EUR";
        bystyle.find_fmt.para_style = "Heading 2";
        assert (Finder.search (p, st, bystyle).size == 2);
        bystyle.find_fmt.para_style = "Body Text";
        assert (Finder.search (p, st, bystyle).size == 0);
        var bold_only = new FindQuery ();
        bold_only.find_fmt.bold = 1;
        var bf = Finder.search (p, st, bold_only);
        assert (bf.size == 1 && bf[0].a.para == 1 && bf[0].a.offset == 0 && bf[0].b.offset == st.paras[1].length ());
        var word = new FindQuery ();
        word.pattern = "or";
        word.whole_word = true;
        assert (Finder.search (p, st, word).size == 1);
        word.whole_word = false;
        assert (Finder.search (p, st, word).size == 1);
        var para_change = new FindQuery ();
        para_change.pattern = "Prices";
        para_change.change_text = false;
        para_change.change_fmt.para_style = "Caption";
        Finder.replace_all (p, new Gee.ArrayList<Story>.wrap ({ st }), para_change);
        assert (st.paras[1].style == "Caption");
    } catch (RegexError e) {
        error (e.message);
    }
    var bad = new FindQuery ();
    bad.grep = true;
    bad.pattern = "([a-";
    bool failed = false;
    try {
        Finder.search (p, st, bad);
    } catch (RegexError e) {
        failed = true;
    }
    assert (failed);
}

void test_find_objects () {
    var p = doc ();
    var os = new ObjectStyle ("Highlight");
    os.proto.fill = new Fill.solid ("#ffee00");
    os.use_stroke = false;
    os.use_effects = false;
    os.use_corner = false;
    os.use_wrap = false;
    os.use_frame = false;
    p.object_styles.add (os);
    for (int i = 0; i < 3; i++) {
        var sh = new ShapeItem (ShapeKind.RECT);
        sh.id = p.next_id ();
        sh.fill = new Fill.solid (i < 2 ? "#ff0000" : "#0000ff");
        p.pages[0].items.add (sh);
    }
    var oq = new ObjectQuery ();
    oq.fill = "#ff0000";
    assert (Finder.find_objects (p, oq).size == 2);
    oq.change_object_style = "Highlight";
    assert (Finder.change_objects (p, oq) == 2);
    int yellow = 0;
    foreach (var it in p.pages[0].items) if (it.fill.color == "#ffee00" && it.object_style == "Highlight") yellow++;
    assert (yellow == 2);
}

void test_anchored_objects () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 300, 300);
    var st = p.story (t.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("Logo ", "Body Text");
    var box = new ShapeItem (ShapeKind.RECT);
    box.id = p.next_id ();
    box.w = 40;
    box.h = 30;
    box.fill = new Fill.solid ("#ff0000");
    para.runs.add (new Run.anchored (box, new AnchorSpec ()));
    para.runs.add (new Run (" after"));
    st.paras.add (para);
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    assert (fr.lines.size == 1);
    assert (fr.lines[0].ascent >= 29.5);
    int xa, xb;
    var line = fr.lines[0];
    line.line ().index_to_x (line.build.anchors[0].disp - line.window, false, out xa);
    line.line ().index_to_x (line.build.anchors[0].disp - line.window + 3, false, out xb);
    assert (Math.fabs ((xb - xa) / (double) Pango.SCALE - 40) < 0.5);
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 300, 300);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    var r = new Renderer (p, cache);
    r.opts.print = true;
    r.draw_page (cr, 0);
    surf.flush ();
    double ax = line.x + line.x_off + xa / (double) Pango.SCALE + 20;
    double ay = line.baseline - 15;
    unowned uchar[] data = surf.get_data ();
    int off = (int) ay * surf.get_stride () + (int) ax * 4;
    assert (data[off + 2] > 200 && data[off + 1] < 60 && data[off] < 60);
    var q = round_trip (p);
    var qr = q.story (t.story).paras[0].runs[1];
    assert (qr.anchor != null && qr.anchor_spec != null && qr.anchor.w == 40);
    var custom = new AnchorSpec ();
    custom.mode = 1;
    custom.x_ref = 1;
    custom.x_offset = 200;
    custom.y_offset = 10;
    para.runs[1].anchor_spec = custom;
    cache.invalidate ();
    var fr2 = cache.story (t.story).frames[0];
    int ya, yb;
    fr2.lines[0].line ().index_to_x (fr2.lines[0].build.anchors[0].disp - fr2.lines[0].window, false, out ya);
    fr2.lines[0].line ().index_to_x (fr2.lines[0].build.anchors[0].disp - fr2.lines[0].window + 3, false, out yb);
    assert (yb == ya);
    var inner = p.add_text_frame (new Gee.ArrayList<Item> (), 0, 0, 80, 30);
    p.story (inner.story).paras[0].runs[0].text = "Inside";
    para.runs.add (new Run.anchored (inner, new AnchorSpec ()));
    assert (p.find_item (inner.id) != null);
    cache.invalidate ();
    var ir = cache.story (inner.story);
    assert (ir.frames.size == 1 && !ir.overset);
}

void test_anchored_wrap () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 300, 400);
    var st = p.story (t.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("Start ", "Body Text");
    var box = new ShapeItem (ShapeKind.RECT);
    box.id = p.next_id ();
    box.w = 100;
    box.h = 60;
    box.wrap = WrapMode.BOUNDING_BOX;
    box.wrap_offset = 5;
    var spec = new AnchorSpec ();
    spec.mode = 1;
    spec.x_ref = 1;
    spec.x_offset = 0;
    spec.y_offset = 4;
    para.runs.add (new Run.anchored (box, spec));
    para.runs.add (new Run ("words that keep going and going so the paragraph needs many lines to fill the frame and pass the anchored box completely"));
    st.paras.add (para);
    st.paras.add (new Paragraph.with_text ("Second paragraph with more words that also flow past the anchored object and below it, long enough to need several lines of text in this frame.", "Body Text"));
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    var first = fr.lines[0];
    double left, top;
    TextEngine.anchor_box (first, first.build.anchors[0], out left, out top);
    assert (Math.fabs (left) < 0.01);
    int beside = 0, below = 0;
    foreach (var l in fr.lines) {
        double y0 = l.baseline - l.ascent, y1 = l.baseline + l.descent;
        if (y1 > top - 5 && y0 < top + 60 + 5 && l != first) {
            assert (l.x + l.x_off >= 104.5);
            beside++;
        } else if (y0 >= top + 65) {
            assert (l.x + l.x_off < 20);
            below++;
        }
    }
    assert (beside >= 2 && below >= 2);
    box.wrap = WrapMode.NONE;
    cache.invalidate ();
    var plain = cache.story (t.story).frames[0];
    foreach (var l in plain.lines) assert (l.x + l.x_off < 20);
}

uint8[] picture (string type, bool shape) {
    var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 200, 200);
    pb.fill ((uint32) 0xffffffffU);
    if (shape) {
        var sub = new Gdk.Pixbuf.subpixbuf (pb, 50, 50, 100, 100);
        sub.fill ((uint32) 0x202020ffU);
    }
    uint8[] buf;
    try {
        pb.save_to_buffer (out buf, type);
    } catch (Error e) {
        error (e.message);
    }
    return buf;
}

ImageFrame image_on (Publication p, string media, uint8[] data) {
    p.media[media] = new Bytes (data);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.media = media;
    im.x = 0;
    im.y = 0;
    im.w = 200;
    im.h = 200;
    im.fit = FitMode.STRETCH;
    im.wrap = WrapMode.CONTOUR;
    im.wrap_offset = 0;
    p.pages[0].items.add (im);
    return im;
}

void test_contour_sources () {
    var p = doc ();
    var tri = new Gee.ArrayList<double?> ();
    foreach (double v in new double[] { 0.5, 0.0, 1.0, 1.0, 0.0, 1.0 }) tri.add (v);
    var res = new ByteArray ();
    res.append (PhotoshopPaths.resource_block (2000, "Cutout", PhotoshopPaths.encode_path (tri, true)));
    var clip = new ByteArray ();
    clip.append ({ 6 });
    clip.append ("Cutout".data);
    clip.append ({ 0, 0 });
    res.append (PhotoshopPaths.resource_block (2999, "", clip.data));
    var jpeg = PhotoshopPaths.with_jpeg_resources (picture ("jpeg", false), res.data);
    var paths = PhotoshopPaths.read (jpeg);
    assert (paths != null && paths.paths.size == 1 && paths.clipping == "Cutout");
    var path = paths.preferred ();
    assert (path.name == "Cutout" && path.subpaths.size == 1 && path.subpaths[0].closed && path.subpaths[0].knots.size == 3);
    assert (Math.fabs (path.subpaths[0].knots[0].x - 0.5) < 1e-6 && Math.fabs (path.subpaths[0].knots[1].y - 1) < 1e-6);
    var im = image_on (p, "tri.jpg", jpeg);
    var store = ImageStore.get_default ();
    double y0, step;
    var rows = store.alpha_rows (p, im, out y0, out step);
    assert (rows != null);
    int n = rows.size / 2;
    double? top_l = rows[2 * 5], top_r = rows[2 * 5 + 1];
    double? bot_l = rows[2 * (n - 3)], bot_r = rows[2 * (n - 3) + 1];
    assert (top_l != null && bot_l != null);
    assert (top_r - top_l < 30);
    assert (bot_r - bot_l > 170);
    assert (Math.fabs ((top_l + top_r) / 2 - 100) < 6);
    im.contour_source = ImageStore.CONTOUR_FRAME;
    assert (store.alpha_rows (p, im, out y0, out step) == null);
    var sq = image_on (p, "square.png", picture ("png", true));
    sq.x = 0;
    sq.contour_source = ImageStore.CONTOUR_EDGES;
    var er = store.alpha_rows (p, sq, out y0, out step);
    assert (er != null);
    int mid = er.size / 4;
    assert (er[2 * mid] != null && Math.fabs (er[2 * mid] - 50) < 3 && Math.fabs (er[2 * mid + 1] - 150) < 3);
    assert (er[0] == null && er[1] == null);
    sq.contour_source = ImageStore.CONTOUR_AUTO;
    assert (store.alpha_rows (p, sq, out y0, out step) == null);
    p.pages[0].items.remove (im);
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 300, 200);
    p.story (t.story).paras[0].runs[0].text = "Text that flows next to the square picture, long enough to need many lines in this frame so the contour is visible in every line of it, and then some more words to fill it. " + string.nfill (1, 'x').replace ("x", "Even more words keep the paragraph going past the picture so that lines beside it and below it both exist in the frame. And still more text follows here.");
    sq.contour_source = ImageStore.CONTOUR_EDGES;
    sq.wrap_side = WrapSide.RIGHT;
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    bool pushed = false, free_top = false;
    foreach (var l in fr.lines) {
        double ly = l.baseline;
        if (ly > 60 && ly < 140) {
            assert (l.x + l.x_off >= 149);
            pushed = true;
        }
        if (ly < 40 && l.x + l.x_off < 5) free_top = true;
    }
    assert (pushed && free_top);
    sq.clip_path = true;
    var q = round_trip (p);
    var back = q.find_item (sq.id).item as ImageFrame;
    assert (back.contour_source == ImageStore.CONTOUR_EDGES && back.clip_path);
}

bool has_kind (Preflight pf, IssueKind k) {
    foreach (var i in pf.issues) if (i.kind == k) return true;
    return false;
}

void test_preflight_profiles () {
    var p = doc ();
    p.settings.cmyk = true;
    p.settings.bleed_top = p.settings.bleed_bottom = p.settings.bleed_inside = p.settings.bleed_outside = 0;
    p.swatches.add (new Swatch.cmyk ("Rich Black", 1, 1, 1, 1));
    p.swatches.add (new Swatch.cmyk ("Gold", 0, 0.2, 0.8, 0.1, true));
    var a = new ShapeItem (ShapeKind.RECT);
    a.id = p.next_id ();
    a.x = 50;
    a.y = 50;
    a.w = 50;
    a.h = 50;
    a.fill = new Fill.solid (ColorRef.swatch ("Rich Black"));
    p.pages[0].items.add (a);
    var b = (ShapeItem) a.clone ();
    b.id = p.next_id ();
    b.x = 120;
    b.fill = new Fill.solid (ColorRef.swatch ("Gold"));
    p.pages[0].items.add (b);
    var t = p.add_text_frame (p.pages[0].items, 50, 200, 200, 40);
    var st = p.story (t.story);
    st.paras[0].runs[0].text = "Tiny legal line";
    st.paras[0].runs[0].fmt.size = 4;
    var print = PreflightProfile.find (p, PreflightProfile.PRINT);
    var pf = new Preflight (p);
    pf.font_check = (f) => true;
    pf.use_profile (print);
    pf.run ();
    assert (has_kind (pf, IssueKind.INK_LIMIT));
    assert (has_kind (pf, IssueKind.BLEED_SETTING));
    assert (has_kind (pf, IssueKind.PRINT_TEXT_SIZE));
    assert (!has_kind (pf, IssueKind.SPOT_COLOR) || pf.count (Severity.ERROR) > 0);
    var basic = new Preflight (p);
    basic.font_check = (f) => true;
    basic.use_profile (PreflightProfile.find (p, PreflightProfile.BASIC));
    basic.run ();
    assert (!has_kind (basic, IssueKind.INK_LIMIT) && !has_kind (basic, IssueKind.BLEED_SETTING) && !has_kind (basic, IssueKind.PRINT_TEXT_SIZE));
    var paper = new Preflight (p);
    paper.font_check = (f) => true;
    paper.use_profile (PreflightProfile.find (p, PreflightProfile.NEWSPAPER));
    paper.run ();
    bool spot_error = false;
    foreach (var i in paper.issues) if (i.kind == IssueKind.SPOT_COLOR && i.severity == Severity.ERROR) spot_error = true;
    assert (spot_error);
    assert (Math.fabs (Preflight.swatch_ink (p.swatch ("Rich Black"), ColorManager.for_settings (p.settings)) - 400) < 0.5);
    p.settings.bleed_top = p.settings.bleed_bottom = p.settings.bleed_inside = p.settings.bleed_outside = 9;
    st.paras[0].runs[0].fmt.size = 9;
    p.swatch ("Rich Black").k = 0.9;
    p.swatch ("Rich Black").c = 0.5;
    p.swatch ("Rich Black").m = 0.4;
    p.swatch ("Rich Black").y = 0.4;
    var again = new Preflight (p);
    again.font_check = (f) => true;
    again.use_profile (print);
    again.run ();
    assert (!has_kind (again, IssueKind.INK_LIMIT) && !has_kind (again, IssueKind.BLEED_SETTING) && !has_kind (again, IssueKind.PRINT_TEXT_SIZE));
    var custom = print.clone ();
    custom.builtin = false;
    custom.name = "Studio";
    custom.ink_limit = 180;
    custom.allow_rgb = true;
    p.preflight_profiles.add (custom);
    p.preflight_profile = "Studio";
    var q = round_trip (p);
    assert (q.preflight_profile == "Studio" && q.preflight_profiles.size == 1);
    var qp = PreflightProfile.find (q, "Studio");
    assert (qp.ink_limit == 180 && qp.allow_rgb && !qp.builtin && Math.fabs (qp.min_bleed - print.min_bleed) < 0.01);
    var studio = new Preflight (q);
    studio.font_check = (f) => true;
    studio.use_profile (qp);
    studio.run ();
    assert (has_kind (studio, IssueKind.INK_LIMIT));
    try {
        var back = PreflightProfile.from_file_text (qp.to_file_text ());
        assert (back.name == "Studio" && back.ink_limit == 180 && back.min_ppi == qp.min_ppi);
        PreflightProfile.from_file_text ("<other/>");
        assert_not_reached ();
    } catch (Error e) {
        assert (e.message.contains ("not a preflight profile"));
    }
    var a11y = PreflightProfile.find (q, PreflightProfile.ACCESSIBLE);
    assert (!a11y.allows (IssueKind.OVERSET) && a11y.allows (IssueKind.ALT_TEXT));
}

const string FILLER = "Long-form books need notes that sit at the foot of the column where they are cited, and the text above has to make room for them. ";

Paragraph para_with_notes (Publication p, string[] notes) {
    var para = new Paragraph.with_text (FILLER + FILLER, "Body Text");
    foreach (string n in notes) {
        para.runs.add (Footnotes.make_run (p, n));
        para.runs.add (new Run (FILLER));
    }
    return para;
}

void test_footnotes () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 50, 50, 300, 420);
    var st = p.story (t.story);
    st.paras.clear ();
    st.paras.add (para_with_notes (p, { "First note.", "Second note, a little longer so that it needs two lines in the narrow note area at the foot.", "Third." }));
    assert (p.styles.find_paragraph (FootnoteOptions.STYLE) != null);
    var cache = new LayoutCache (p);
    var res = cache.story (t.story);
    var fr = res.frames[0];
    assert (fr.notes.size == 3);
    double text_bottom = 0;
    foreach (var l in fr.lines) text_bottom = double.max (text_bottom, l.baseline + l.descent);
    double first_note = double.MAX, last_note_bottom = 0;
    for (int i = 0; i < 3; i++) {
        var n = fr.notes[i];
        assert (n.number == i + 1);
        first_note = double.min (first_note, n.y);
        last_note_bottom = double.max (last_note_bottom, n.y + n.height);
        string txt = n.box.lines.size > 0 ? n.box.lines[0].build.text : "";
        assert (txt.has_prefix ("%d\u2002".printf (i + 1)));
    }
    assert (fr.notes[1].height > fr.notes[0].height + 3);
    assert (last_note_bottom <= 420 + 0.5);
    assert (text_bottom <= first_note - p.footnotes.space_before + 0.5);
    var refs = 0;
    foreach (var l in fr.lines) foreach (var nr in l.build.notes) refs++;
    assert (refs >= 3);
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 400, 520);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    var r = new Renderer (p, cache);
    r.opts.print = true;
    r.draw_page (cr, 0);
    surf.flush ();
    unowned uint8[] px = surf.get_data ();
    int ry = (int) (50 + first_note - p.footnotes.space_before / 2);
    bool rule = false;
    for (int dy = -1; dy <= 1; dy++) {
        int off = (ry + dy) * surf.get_stride () + 60 * 4;
        if (px[off] < 230) rule = true;
    }
    assert (rule);
    p.footnotes.numbering = 2;
    p.footnotes.rule = false;
    cache.invalidate ();
    var r2 = cache.story (t.story).frames[0];
    assert (r2.notes.size == 3 && r2.notes[2].box.lines[0].build.text.has_prefix ("III\u2002"));
    bool roman_ref = false;
    foreach (var l in r2.lines) if (l.build.text.contains ("II")) roman_ref = true;
    assert (roman_ref);
    p.footnotes.numbering = 0;
    var q = round_trip (p);
    assert (q.footnotes.rule == false);
    var qs = q.story (t.story);
    int found = 0;
    foreach (var pp in qs.paras) foreach (var rr in pp.runs) if (rr.note != null) {
        found++;
        if (found == 2) assert (rr.note.plain_text ().has_prefix ("Second note"));
    }
    assert (found == 3);
    var crowded = doc ();
    var ct = crowded.add_text_frame (crowded.pages[0].items, 0, 0, 300, 300);
    var cs = crowded.story (ct.story);
    cs.paras.clear ();
    for (int i = 0; i < 6; i++) cs.paras.add (new Paragraph.with_text (FILLER + FILLER, "Body Text"));
    var plain = new LayoutCache (crowded).story (ct.story);
    int plain_lines = plain.frames[0].lines.size;
    cs.paras[0].runs.add (Footnotes.make_run (crowded, FILLER + FILLER + FILLER));
    var with_notes = new LayoutCache (crowded).story (ct.story);
    assert (with_notes.frames[0].lines.size < plain_lines);
    assert (with_notes.overset);
}

void test_footnote_restart () {
    var p = doc ();
    var a = p.add_text_frame (p.pages[0].items, 50, 50, 300, 300);
    var b = p.add_text_frame (p.pages[1].items, 50, 50, 300, 300);
    p.link_frames (a, b);
    var st = p.story (a.story);
    st.paras.clear ();
    for (int i = 0; i < 8; i++) st.paras.add (para_with_notes (p, { "Note %d.".printf (i + 1) }));
    var cache = new LayoutCache (p);
    var res = cache.story (a.story);
    assert (res.frames.size == 2 && res.frames[0].notes.size > 0 && res.frames[1].notes.size > 0);
    int last_first = res.frames[0].notes[res.frames[0].notes.size - 1].number;
    assert (res.frames[1].notes[0].number == last_first + 1);
    p.footnotes.restart = 1;
    cache.invalidate ();
    var paged = cache.story (a.story);
    assert (paged.frames[0].notes[0].number == 1);
    assert (paged.frames[1].notes[0].number == 1);
    var other = p.add_text_frame (p.pages[1].items, 50, 380, 300, 200);
    var os = p.story (other.story);
    os.paras.clear ();
    os.paras.add (para_with_notes (p, { "Own story note." }));
    p.footnotes.restart = 3;
    cache.invalidate ();
    assert (cache.story (other.story).frames[0].notes[0].number == 1);
    p.footnotes.restart = 0;
    cache.invalidate ();
    assert (cache.story (other.story).frames[0].notes[0].number == 9);
}

void test_footnote_split () {
    var p = doc ();
    var a = p.add_text_frame (p.pages[0].items, 50, 50, 300, 260);
    var b = p.add_text_frame (p.pages[1].items, 50, 50, 300, 260);
    p.link_frames (a, b);
    var st = p.story (a.story);
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text (FILLER + FILLER + FILLER + FILLER + FILLER, "Body Text"));
    var long_note = new StringBuilder ();
    for (int i = 0; i < 40; i++) long_note.append ("A very long note that continues for many lines. ");
    st.paras[0].runs.add (Footnotes.make_run (p, long_note.str));
    st.paras[0].runs.add (new Run (FILLER + FILLER));
    var cache = new LayoutCache (p);
    var res = cache.story (a.story);
    assert (res.frames[0].notes.size == 1 && res.frames[1].notes.size >= 1);
    var head = res.frames[0].notes[0];
    var tail = res.frames[1].notes[0];
    assert (!head.continued && tail.continued && head.note == tail.note);
    assert (head.y + head.height <= 260 + 0.5);
    assert (tail.box.lines[0].baseline - tail.box.lines[0].ascent < 0.5);
    p.footnotes.split = false;
    cache.invalidate ();
    var whole = cache.story (a.story);
    int pieces = 0;
    foreach (var fr in whole.frames) foreach (var n in fr.notes) pieces++;
    assert (pieces == 1);
}

void test_endnotes () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 50, 50, 300, 300);
    var st = p.story (t.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("Claim one", "Body Text");
    para.runs.add (Footnotes.make_endnote (p, "Source for claim one."));
    para.runs.add (new Run (" and a footnote"));
    para.runs.add (Footnotes.make_run (p, "Foot."));
    para.runs.add (new Run (" and claim two"));
    para.runs.add (Footnotes.make_endnote (p, "Source for claim two."));
    st.paras.add (para);
    int pages = p.pages.size;
    assert (Footnotes.update_endnotes (p, "Notes") == 2);
    assert (p.pages.size == pages + 1 && p.endnote_story != 0);
    var es = p.story (p.endnote_story);
    assert (es.paras.size == 3 && es.paras[0].text () == "Notes");
    assert (es.paras[1].text ().has_prefix ("1.") && es.paras[1].text ().contains ("claim one"));
    assert (es.paras[2].text ().has_prefix ("2.") && es.paras[2].style == FootnoteOptions.END_STYLE);
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    assert (fr.notes.size == 1 && fr.notes[0].number == 1);
    var line = fr.lines[0].build.text;
    assert (line.contains ("one1") && line.contains ("two2") && line.contains ("footnote1"));
    para.runs.insert (0, Footnotes.make_endnote (p, "Earlier."));
    assert (Footnotes.update_endnotes (p, "Notes") == 3);
    assert (p.pages.size == pages + 1);
    assert (es.paras[1].text ().contains ("Earlier") && es.paras[2].text ().has_prefix ("2."));
    var q = round_trip (p);
    assert (q.endnote_story == p.endnote_story);
    int ends = 0;
    foreach (var pp in q.story (t.story).paras) foreach (var r in pp.runs) if (Footnotes.is_endnote (r)) ends++;
    assert (ends == 3);
}

string first_text (LayoutCache c, int story) {
    var sb = new StringBuilder ();
    foreach (var fr in c.story (story).frames) foreach (var l in fr.lines) if (l.para_first) sb.append (l.build.text + "|");
    return sb.str;
}

void test_cross_references () {
    var p = doc ();
    var src = p.add_text_frame (p.pages[0].items, 50, 50, 300, 300);
    var dst = p.add_text_frame (p.pages[1].items, 50, 50, 300, 300);
    var ds = p.story (dst.story);
    ds.paras.clear ();
    var head = new Paragraph.with_text ("Getting Started", "Body Text");
    head.anchor = "intro";
    ds.paras.add (head);
    var item = new Paragraph.with_text ("Install the press", "Body Text");
    item.fmt.list_type = 2;
    item.anchor = "step";
    ds.paras.add (item);
    var ss = p.story (src.story);
    ss.paras.clear ();
    var para = new Paragraph.with_text ("See ", "Body Text");
    ss.paras.add (para);
    ss.insert_field (TextPos (0, 4), Fields.xref (0, "intro"));
    ss.insert_text (TextPos (0, 5), ", page ");
    ss.insert_field (TextPos (0, 12), Fields.xref (2, "intro"));
    ss.insert_text (TextPos (0, 13), ", step ");
    ss.insert_field (TextPos (0, 20), Fields.xref (3, "step"));
    ss.insert_text (TextPos (0, 21), " ");
    ss.insert_field (TextPos (0, 22), Fields.xref (6, "step"));
    ss.insert_text (TextPos (0, 23), " and ");
    ss.insert_field (TextPos (0, 28), Fields.xref (1, "gone"));
    var cache = new LayoutCache (p);
    string t = first_text (cache, src.story);
    assert (t.contains ("“Getting Started” on page 2"));
    assert (t.contains ("page 2, step 1."));
    assert (t.contains ("on page 2 and"));
    assert (t.contains ("[missing: gone]"));
    bool linked = false;
    foreach (var l in cache.story (src.story).frames[0].lines) foreach (var sp in l.build.spans) if (sp.fmt.link == "page:1") linked = true;
    assert (linked);
    p.add_page (0, p.pages[0].master);
    cache.invalidate_story (dst.story);
    assert (first_text (cache, src.story).contains ("on page 3"));
    var q = round_trip (p);
    assert (q.story (dst.story).paras[0].anchor == "intro");
    var qc = new LayoutCache (q);
    assert (first_text (qc, src.story).contains ("“Getting Started” on page 3"));
}

void test_index () {
    var p = doc ();
    var a = p.add_text_frame (p.pages[0].items, 50, 50, 300, 300);
    var b = p.add_text_frame (p.pages[1].items, 50, 50, 300, 300);
    var sa = p.story (a.story);
    sa.paras.clear ();
    sa.paras.add (new Paragraph.with_text ("Zebra crossing and apples and the Ångström unit", "Body Text"));
    sa.insert_field (TextPos (0, 5), IndexMarker.field_for ({ "Zebra" }));
    sa.insert_field (TextPos (0, 0), IndexMarker.field_for ({ "Apple", "Golden" }));
    sa.insert_field (TextPos (0, 0), IndexMarker.field_for ({ "Ångström" }));
    sa.insert_field (TextPos (0, 0), IndexMarker.field_for ({ "Pome" }, IndexMarker.SEE, "Apple"));
    var sb = p.story (b.story);
    sb.paras.clear ();
    sb.paras.add (new Paragraph.with_text ("More zebras here", "Body Text"));
    sb.insert_field (TextPos (0, 4), IndexMarker.field_for ({ "Zebra" }));
    sb.insert_field (TextPos (0, 0), IndexMarker.field_for ({ "Apple" }, IndexMarker.SEE_ALSO, "Pome"));
    p.add_page (-1, p.pages[0].master);
    var c = p.add_text_frame (p.pages[2].items, 50, 50, 300, 300);
    var sc = p.story (c.story);
    sc.paras.clear ();
    sc.paras.add (new Paragraph.with_text ("Third zebra", "Body Text"));
    sc.insert_field (TextPos (0, 0), IndexMarker.field_for ({ "Zebra" }));
    var m = IndexMarker.parse (IndexMarker.field_for ({ "A|b", "c d" }, IndexMarker.SEE, "x|y"));
    assert (m.topics.length == 2 && m.topics[0] == "A|b" && m.target == "x|y" && m.kind == IndexMarker.SEE);
    var cache = new LayoutCache (p);
    assert (!first_text (cache, a.story).contains ("idx"));
    var s = new IndexSettings ();
    s.title = "Index";
    s.language = "en_US";
    int pages = p.pages.size;
    int n = IndexBuilder.generate (p, s);
    assert (n == 4 && p.pages.size == pages + 1 && p.index != null && p.index.story == s.story);
    var lines = new Gee.ArrayList<string> ();
    foreach (var para in p.story (s.story).paras) lines.add (para.text ());
    string all = string.joinv ("\n", lines.to_array ());
    assert (lines[0] == "Index");
    assert (all.contains ("Zebra, 1" + IndexBuilder.RANGE_DASH + "3"));
    assert (all.contains ("Apple. See also Pome"));
    assert (all.contains ("Golden, 1"));
    assert (all.contains ("Pome. See Apple"));
    int ia = lines.index_of ("A"), iz = lines.index_of ("Z"), ip = lines.index_of ("P");
    assert (ia > 0 && ip > ia && iz > ip);
    int iang = -1;
    for (int i = 0; i < lines.size; i++) if (lines[i].has_prefix ("Ångström")) iang = i;
    assert (iang > ia && iang < ip);
    bool level2 = false;
    foreach (var para in p.story (s.story).paras) if (para.text ().has_prefix ("Golden") && para.style == IndexBuilder.level_style (p, 2)) level2 = true;
    assert (level2);
    assert (IndexBuilder.generate (p, s) == 4 && p.pages.size == pages + 1);
    s.language = "sv_SE";
    s.headings = false;
    IndexBuilder.generate (p, s);
    var sv = new Gee.ArrayList<string> ();
    foreach (var para in p.story (s.story).paras) sv.add (para.text ());
    int sz = -1, sang = -1;
    for (int i = 0; i < sv.size; i++) {
        if (sv[i].has_prefix ("Zebra")) sz = i;
        if (sv[i].has_prefix ("Ångström")) sang = i;
    }
    assert (sz > 0 && sang > sz);
    assert (IndexBuilder.sort_key ("Ñandú", "es_ES") > IndexBuilder.sort_key ("Nube", "es_ES"));
    s.language = "en_US";
    var q = round_trip (p);
    assert (q.index != null && q.index.language == "en_US" && q.index.story == s.story);
}

uint8[] pixel (Publication p, int x, int y) {
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 300, 300);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_page (cr, 0);
    surf.flush ();
    unowned uint8[] d = surf.get_data ();
    int o = y * surf.get_stride () + x * 4;
    return { d[o + 2], d[o + 1], d[o] };
}

void test_table_styles () {
    var p = doc ();
    var th = new ParagraphStyle ("Table Head", StyleSheet.BASIC);
    th.chars.bold = 1;
    p.styles.paragraph.add (th);
    var head = new CellStyle ("Head Cell");
    head.fill = "#cc0000";
    head.valign = 1;
    head.para_style = "Table Head";
    p.cell_styles.add (head);
    var dark = new CellStyle ("Dark Head");
    dark.based_on = "Head Cell";
    dark.fill = "#0000cc";
    p.cell_styles.add (dark);
    var body = new CellStyle ("Body Cell");
    body.diagonal = 1;
    p.cell_styles.add (body);
    var ts = new TableStyle ("Price List");
    ts.header_cell = "Head Cell";
    ts.body_cell = "Body Cell";
    ts.alt_fill = "#00cc00";
    ts.border_width = 0;
    p.table_styles.add (ts);
    var t = new TableItem (4, 2);
    t.id = p.next_id ();
    t.x = 0;
    t.y = 0;
    t.w = 200;
    t.h = 160;
    t.init_cells (p);
    t.header_rows = 1;
    t.border_width = 1;
    p.pages[0].items.add (t);
    TableStyles.apply_table (p, t, "Price List");
    assert (t.table_style == "Price List" && t.alt_fill == "#00cc00" && t.border_width == 0);
    assert (t.cell (0, 0).story.paras[0].style == "Table Head" && t.cell (1, 0).story.paras[0].style == StyleSheet.BASIC);
    var px = pixel (p, 50, 20);
    assert (px[0] > 180 && px[1] < 40 && px[2] < 40);
    var alt = pixel (p, 50, 100);
    assert (alt[1] > 180 && alt[0] < 40);
    var eff = TableStyles.effective_cell (p, t, 1, 0);
    assert (eff != null && eff.diagonal == 1 && eff.name == "Body Cell");
    TableStyles.apply_cell (p, t.cell (0, 1), "Dark Head");
    var dh = TableStyles.resolve_cell (p, "Dark Head");
    assert (dh.fill == "#0000cc" && dh.valign == 1 && dh.para_style == "Table Head");
    var blue = pixel (p, 150, 20);
    assert (blue[2] > 180 && blue[0] < 40);
    head.fill = "#ffcc00";
    ts.alt_fill = "#cccccc";
    assert (TableStyles.update_all (p) == 1);
    var yellow = pixel (p, 50, 20);
    assert (yellow[0] > 230 && yellow[1] > 180 && yellow[2] < 40);
    assert (t.alt_fill == "#cccccc");
    var q = round_trip (p);
    assert (q.table_styles.size == 1 && q.cell_styles.size == 3);
    var qt = q.find_item (t.id).item as TableItem;
    assert (qt.table_style == "Price List" && qt.cell (0, 1).cell_style == "Dark Head");
    assert (TableStyles.find_cell (q, "Dark Head").based_on == "Head Cell");
}

CharFormat fmt_at (ParaBuild b, string needle) {
    int at = b.text.index_of (needle);
    assert (at >= 0);
    foreach (var sp in b.spans) if (sp.start <= at && sp.end > at) return sp.fmt;
    assert_not_reached ();
}

void test_nested_grep_styles () {
    var p = doc ();
    var bold = new CharacterStyle ("Lead");
    bold.chars.bold = 1;
    p.styles.character.add (bold);
    var ital = new CharacterStyle ("Soft");
    ital.chars.italic = 1;
    p.styles.character.add (ital);
    var num = new CharacterStyle ("Number");
    num.chars.color = "#ff0000";
    p.styles.character.add (num);
    var recipe = new ParagraphStyle ("Recipe", StyleSheet.BASIC);
    var n1 = new NestedStyle ("Lead");
    n1.unit = NestedUnit.CHARACTER;
    n1.character = ":";
    n1.count = 1;
    n1.through = true;
    recipe.nested.add (n1);
    var n2 = new NestedStyle ("Soft");
    n2.unit = NestedUnit.WORDS;
    n2.count = 2;
    n2.through = false;
    recipe.nested.add (n2);
    recipe.grep.add (new GrepStyle ("Number", "\\d+"));
    p.styles.paragraph.add (recipe);
    var child = new ParagraphStyle ("Recipe Note", "Recipe");
    p.styles.paragraph.add (child);
    var fc = new FieldContext (p);
    var counter = new ListCounter ();
    var para = new Paragraph.with_text ("Flour: two cups of sugar and 250 grams", "Recipe Note");
    var b = ParaBuild.build (p, para, 0, fc, counter, false);
    assert (fmt_at (b, "Flour").bold == 1 && fmt_at (b, ":").bold == 1);
    assert (fmt_at (b, "two").italic == 1 && fmt_at (b, "cups").italic == 1);
    assert (fmt_at (b, "cups").bold != 1);
    assert (fmt_at (b, "sugar").italic != 1);
    assert (fmt_at (b, "250").color == "#ff0000" && fmt_at (b, "grams").color != "#ff0000");
    int covered = 0;
    foreach (var sp in b.spans) covered += sp.end - sp.start;
    assert (covered == b.text.length);
    recipe.grep[0].pattern = "[";
    var bad = ParaBuild.build (p, para, 0, fc, counter, false);
    assert (fmt_at (bad, "250").color != "#ff0000");
    recipe.grep[0].pattern = "\\d+";
    var q = round_trip (p);
    var qr = q.styles.find_paragraph ("Recipe");
    assert (qr.nested.size == 2 && qr.nested[0].unit == NestedUnit.CHARACTER && qr.nested[0].character == ":" && !qr.nested[1].through && qr.nested[1].count == 2);
    assert (qr.grep.size == 1 && qr.grep[0].pattern == "\\d+");
    var cache = new LayoutCache (p);
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 300, 100);
    p.story (t.story).paras.clear ();
    p.story (t.story).paras.add (para);
    var fr = cache.story (t.story).frames[0];
    assert (fr.lines.size >= 1);
}

void test_optical_margins () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 240, 400);
    var st = p.story (t.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("\u201CQuoted openings and full stops hang into the margin so the edge of the column looks straight to the eye, which is what optical margin alignment does in every book.\u201D", "Body Text");
    para.fmt.align = (int) TextAlign.JUSTIFY;
    st.paras.add (para);
    var cache = new LayoutCache (p);
    var plain = cache.story (t.story).frames[0].lines[0];
    double x_plain = plain.x;
    double w_plain = plain.width;
    para.fmt.optical = 1;
    cache.invalidate ();
    var hung = cache.story (t.story).frames[0].lines[0];
    assert (hung.x < x_plain - 2);
    assert (hung.width >= w_plain + 2);
    assert (TextEngine.optical_factor (0x201C) == 1.0 && TextEngine.optical_factor ('-') == 0.75 && TextEngine.optical_factor ('m') == 0);
    para.fmt.composer = 1;
    para.fmt.align = (int) TextAlign.LEFT;
    cache.invalidate ();
    var single = cache.story (t.story).frames[0].lines[0];
    assert (single.x < x_plain - 2);
    var q = round_trip (p);
    assert (q.story (t.story).paras[0].fmt.optical == 1);
}

double ink_width (string font, string? variations) {
    var f = CharFormat.defaults ();
    f.font = font;
    f.size = 40;
    f.variations = variations;
    var layout = new Pango.Layout (TextEngine.context ());
    layout.set_font_description (TextEngine.font_desc (f));
    layout.set_text ("Harbour", -1);
    Pango.Rectangle ink, logical;
    layout.get_extents (out ink, out logical);
    return logical.width / (double) Pango.SCALE;
}

void test_variable_fonts () {
    var data = FontAxes.build_fvar_font ({ new FontAxis ("wght", 100, 400, 900), new FontAxis ("wdth", 75, 100, 125) });
    var axes = FontAxes.parse (data);
    assert (axes.size == 2 && axes[0].tag == "wght" && axes[0].min == 100 && axes[0].def == 400 && axes[0].max == 900);
    assert (axes[1].tag == "wdth" && axes[1].label () == "Width");
    var v = FontAxes.values ("wght=650, wdth=80");
    assert (v.size == 2 && v["wght"] == 650 && v["wdth"] == 80);
    v["wght"] = 700;
    assert (FontAxes.join (v) == "wdth=80,wght=700");
    var cf = new CharFormat ();
    cf.variations = "wght=700";
    var back = CharFormat.defaults ();
    back.apply (cf);
    assert (back.variations == "wght=700" && TextEngine.font_desc (back).get_variations () == "wght=700");
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 300, 100);
    p.story (t.story).paras[0].runs[0].text = "Weight";
    p.story (t.story).paras[0].runs[0].fmt.variations = "wght=700";
    var q = round_trip (p);
    assert (q.story (t.story).paras[0].runs[0].fmt.variations == "wght=700");
    var real = FontAxes.for_family ("Cantarell");
    if (real.size > 0) {
        FontAxis? w = null;
        foreach (var a in real) if (a.tag == "wght") w = a;
        assert (w != null && w.min < w.max);
        double thin = ink_width ("Cantarell", "wght=%g".printf (w.min));
        double heavy = ink_width ("Cantarell", "wght=%g".printf (w.max));
        assert (heavy > thin + 1);
    } else {
        print ("no variable font installed, rendering check skipped\n");
    }
}

void test_rtl_complex_scripts () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 300, 300);
    t.inset_left = t.inset_right = t.inset_top = t.inset_bottom = 0;
    var st = p.story (t.story);
    st.paras.clear ();
    var ar = new Paragraph.with_text ("abc مرحبا بالعالم", "Body Text");
    ar.runs[0].fmt.font = "Noto Sans Arabic";
    ar.fmt.direction = 1;
    st.paras.add (ar);
    var hi = new Paragraph.with_text ("हिन्दी भाषा", "Body Text");
    hi.runs[0].fmt.font = "Noto Sans Devanagari";
    st.paras.add (hi);
    var cache = new LayoutCache (p);
    var fr = cache.story (t.story).frames[0];
    LaidLine? la = null, lh = null;
    foreach (var l in fr.lines) {
        if (l.para == 0 && la == null) la = l;
        if (l.para == 1 && lh == null) lh = l;
    }
    Pango.Rectangle ink, logical;
    la.line ().get_extents (out ink, out logical);
    double right = la.x + la.x_off + logical.width / (double) Pango.SCALE * la.hscale;
    assert (Math.fabs (right - 300) < 1.5);
    assert (la.build.pf.text_align () == TextAlign.RIGHT || la.build.pf.text_align () == TextAlign.JUSTIFY);
    int xa, xm;
    la.line ().index_to_x (0, false, out xa);
    la.line ().index_to_x (4, false, out xm);
    assert (xa > xm);
    lh.line ().get_extents (out ink, out logical);
    double left = lh.x + lh.x_off;
    assert (left < 1.5);
    unowned SList<Pango.LayoutRun> runs = lh.line ().runs;
    int glyphs = 0;
    for (unowned SList<Pango.LayoutRun> r = runs; r != null; r = r.next) glyphs += r.data.glyphs.num_glyphs;
    assert (glyphs > 0 && glyphs < "हिन्दी भाषा".char_count ());
    string word = ar.runs[0].text.substring (4);
    var longp = new Paragraph.with_text (string.joinv (" ", { word, word, word, word, word, word, word, word, word, word, word, word, word }), "Body Text");
    longp.runs[0].fmt.font = "Noto Sans Arabic";
    longp.fmt.direction = 1;
    st.paras.add (longp);
    cache.invalidate ();
    var fr2 = cache.story (t.story).frames[0];
    LaidLine? last_line = null;
    int count = 0;
    foreach (var l in fr2.lines) if (l.para == 2) {
        last_line = l;
        count++;
    }
    assert (count >= 2);
    last_line.line ().get_extents (out ink, out logical);
    double end = last_line.x + last_line.x_off + logical.width / (double) Pango.SCALE * last_line.hscale;
    assert (Math.fabs (end - 300) < 1.5);
    var q = round_trip (p);
    assert (q.story (t.story).paras[0].fmt.direction == 1);
}

void test_mixed_page_sizes () {
    var settings = new DocSettings ();
    settings.width = 200;
    settings.height = 300;
    settings.facing = true;
    settings.start_left = false;
    settings.set_bleed (0);
    var p = Publication.create (settings, 5);
    p.pages[3].join_prev = true;
    p.pages[3].width = 150;
    p.pages[3].height = 300;
    p.pages[0].width = 220;
    var sp = p.spreads ();
    assert (sp.size == 3);
    assert (sp[0].pages.size == 1 && sp[1].pages.size == 3 && sp[1].pages[2] == 3 && sp[2].pages[0] == 4);
    assert (!p.is_left_page (3) && p.is_left_page (4) && p.is_left_page (1));
    assert (p.page_rect (3).w == 150 && p.page_rect (2).w == 200 && p.page_rect (0).w == 220);
    assert (p.margin_rect (3).w < 150);
    var o = new ExportOptions ();
    o.spreads = true;
    var ex = new Exporter (p, o);
    var sheets = ex.sheets ();
    assert (sheets.size == 3);
    double inner = 0;
    foreach (var sl in sheets[1].slots) inner += sl.w;
    assert (sheets[1].slots.size == 3 && Math.fabs (inner - 550) < 0.01);
    assert (Math.fabs (sheets[1].slots[2].x - sheets[1].slots[1].x - 200) < 0.01);
    var single = new Exporter (p, new ExportOptions ()).sheets ();
    assert (single.size == 5 && Math.fabs (single[0].w - (220 + 2 * single[0].slots[0].x)) < 0.5 && Math.fabs (single[3].slots[0].w - 150) < 0.01);
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-sizes-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string pdf = Path.build_filename (dir, "sizes.pdf");
    try {
        new Exporter (p, new ExportOptions ()).export_pdf (pdf);
    } catch (Error e) {
        error (e.message);
    }
    if (Environment.find_program_in_path ("pdfinfo") != null) {
        string out_s;
        int status;
        try {
            Process.spawn_sync (null, { "pdfinfo", "-f", "1", "-l", "5", pdf }, null, SpawnFlags.SEARCH_PATH, null, out out_s, null, out status);
        } catch (Error e) {
            error (e.message);
        }
        assert (out_s.contains ("Page    1 size:  220 x 300") && out_s.contains ("Page    4 size:  150 x 300") && out_s.contains ("Page    2 size:  200 x 300"));
    }
    var q = round_trip (p);
    assert (q.pages[3].join_prev && q.pages[3].width == 150 && q.pages[2].width.is_nan ());
}

string save_spub (string dir, string name, Publication p) {
    string path = Path.build_filename (dir, name);
    try {
        FileUtils.set_data (path, NativeFormat.write (p));
    } catch (Error e) {
        error (e.message);
    }
    return path;
}

Publication chapter (string title, string body, int pages, double body_size) {
    var p = doc ();
    while (p.pages.size < pages) p.add_page (-1, p.pages[0].master);
    while (p.pages.size > pages) p.pages.remove_at (p.pages.size - 1);
    p.styles.find_paragraph ("Body Text").chars.size = body_size;
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 400);
    var st = p.story (t.story);
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text (title, "Heading 1"));
    st.paras.add (new Paragraph.with_text (body, "Body Text"));
    st.insert_field (TextPos (1, 0), IndexMarker.field_for ({ body }));
    return p;
}

void test_books () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-book-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    var front = doc ();
    while (front.pages.size > 1) front.pages.remove_at (front.pages.size - 1);
    var tf = front.add_text_frame (front.pages[0].items, 40, 40, 300, 400);
    var b = new Book ();
    b.path = Path.build_filename (dir, "harbour." + Book.EXTENSION);
    b.name = "Harbour Book";
    b.docs.add (new BookEntry (save_spub (dir, "front.spub", front)));
    b.docs.add (new BookEntry (save_spub (dir, "one.spub", chapter ("Chapter One", "Piers", 3, 10))));
    b.docs.add (new BookEntry (save_spub (dir, "two.spub", chapter ("Chapter Two", "Tides", 2, 14))));
    b.style_source = 1;
    try {
        b.save ();
        var loaded = Book.load (b.path);
        assert (loaded.docs.size == 3 && loaded.name == "Harbour Book" && loaded.style_source == 1);
        assert (loaded.docs[1].path == b.docs[1].path);
        assert (b.paginate () == 6);
        var two = b.open_doc (2);
        assert (two.page_label (0) == "5" && two.page_label (1) == "6");
        assert (b.open_doc (1).page_label (0) == "2");
        assert (b.sync_styles () == 2);
        assert (b.open_doc (2).styles.find_paragraph ("Body Text").chars.size == 10);
        var all = b.combine ();
        assert (all.pages.size == 6 && all.page_label (5) == "6" && all.meta.title == "Harbour Book");
        int texts = 0;
        all.walk ((r) => {
            if (r.item is TextFrame) texts++;
            return true;
        });
        assert (texts == 3);
        var ts = new TocSettings ();
        ts.title = "Contents";
        ts.levels.add (new TocLevel ("Heading 1", 1, ""));
        ts.story = tf.story;
        assert (b.generate_toc (0, ts) == 2);
        var fp = b.open_doc (0);
        string toc = fp.story (tf.story).plain_text ();
        assert (toc.contains ("Chapter One\t2") && toc.contains ("Chapter Two\t5"));
        var ix = new IndexSettings ();
        assert (b.generate_index (2, ix) == 2);
        var last = b.open_doc (2);
        string idx = last.story (ix.story).plain_text ();
        assert (idx.contains ("Piers, 2") && idx.contains ("Tides, 5"));
        string pdf = Path.build_filename (dir, "book.pdf");
        assert (b.export_pdf (pdf, new ExportOptions ()) == 7);
    } catch (Error e) {
        error (e.message);
    }
}

void test_conditional_text () {
    var p = doc ();
    p.conditions.add (new TextCondition ("Print"));
    p.conditions.add (new TextCondition ("Web"));
    var t = p.add_text_frame (p.pages[0].items, 0, 0, 400, 100);
    var st = p.story (t.story);
    st.paras.clear ();
    var para = new Paragraph.with_text ("Call ", "Body Text");
    var pr = new Run ("0123 456");
    pr.condition = "Print";
    para.runs.add (pr);
    var web = new Run ("example.org");
    web.condition = "Web";
    para.runs.add (web);
    para.runs.add (new Run (" today."));
    st.paras.add (para);
    var cache = new LayoutCache (p);
    string all = cache.story (t.story).frames[0].lines[0].build.text;
    assert (all.contains ("0123 456") && all.contains ("example.org"));
    p.conditions[1].visible = false;
    p.condition_sets.add (Conditions.capture (p, "Print Edition"));
    cache.invalidate ();
    var line = cache.story (t.story).frames[0].lines[0];
    assert (line.build.text == "Call 0123 456 today.");
    assert (line.build.disp_of (13) == line.build.disp_of (24));
    p.conditions[0].visible = false;
    p.conditions[1].visible = true;
    cache.invalidate ();
    assert (cache.story (t.story).frames[0].lines[0].build.text == "Call example.org today.");
    Conditions.apply_set (p, p.condition_sets[0]);
    assert (p.conditions[0].visible && !p.conditions[1].visible && p.active_condition_set == "Print Edition");
    var q = round_trip (p);
    assert (q.conditions.size == 2 && !q.conditions[1].visible && q.condition_sets.size == 1 && q.condition_sets[0].states["Web"] == false);
    assert (q.story (t.story).paras[0].runs[2].condition == "Web");
    var qc = new LayoutCache (q);
    assert (qc.story (t.story).frames[0].lines[0].build.text == "Call 0123 456 today.");
}

void test_separation_preview () {
    var p = doc ();
    p.settings.cmyk = true;
    p.swatches.add (new Swatch.cmyk ("Gold Spot", 0, 0.2, 0.8, 0.1, true));
    var a = new ShapeItem (ShapeKind.RECT);
    a.id = p.next_id ();
    a.x = 10;
    a.y = 10;
    a.w = 100;
    a.h = 100;
    a.fill = new Fill.solid (ColorRef.swatch ("Cyan"));
    p.pages[0].items.add (a);
    var b = (ShapeItem) a.clone ();
    b.id = p.next_id ();
    b.x = 60;
    b.fill = new Fill.solid (ColorRef.swatch ("Magenta"));
    p.pages[0].items.add (b);
    var c = (ShapeItem) a.clone ();
    c.id = p.next_id ();
    c.x = 200;
    c.fill = new Fill.solid (ColorRef.swatch ("Gold Spot"));
    p.pages[0].items.add (c);
    var sp = new SeparationPreview (p);
    assert (sp.enabled.contains ("Gold Spot") && sp.enabled.contains (Inks.CYAN));
    sp.render (0, 1);
    var only_c = sp.ink_at (30, 50);
    assert (only_c[Inks.CYAN] > 95 && only_c[Inks.MAGENTA] < 5);
    var overlap = sp.ink_at (80, 50);
    assert (overlap[Inks.MAGENTA] > 95 && overlap[Inks.CYAN] < 5);
    assert (sp.ink_at (250, 50)["Gold Spot"] > 95 && sp.ink_at (250, 50)[Inks.YELLOW] < 5);
    b.overprint_fill = true;
    sp.render (0, 1);
    var op = sp.ink_at (80, 50);
    assert (op[Inks.MAGENTA] > 95 && op[Inks.CYAN] > 95);
    assert (Math.fabs (sp.total_at (80, 50) - 200) < 3);
    unowned uint8[] d = sp.composite.get_data ();
    int o = 50 * sp.composite.get_stride () + 80 * 4;
    assert (d[o + 2] < 60 && d[o] > 90);
    sp.enabled.remove (Inks.MAGENTA);
    sp.build_composite ();
    d = sp.composite.get_data ();
    assert (d[o + 2] < 30 && d[o + 1] > 140 && d[o] > 200);
    int o2 = 50 * sp.composite.get_stride () + 250 * 4;
    sp.enabled.remove ("Gold Spot");
    sp.build_composite ();
    d = sp.composite.get_data ();
    assert (d[o2] > 250 && d[o2 + 1] > 250 && d[o2 + 2] > 250);
}

void test_signatures () {
    var settings = new DocSettings ();
    settings.width = 100;
    settings.height = 150;
    var p = Publication.create (settings, 20);
    var o = new ExportOptions ();
    o.impose = ImposeMode.SIGNATURES;
    o.signature = 16;
    o.sheet_w = 600;
    o.sheet_h = 400;
    o.creep = 0.5;
    var ex = new Exporter (p, o);
    var sheets = ex.sheets ();
    assert (sheets.size == 4);
    var front = sheets[0];
    assert (front.slots.size == 8);
    var pos = new Gee.HashMap<int, SheetSlot> ();
    foreach (var sl in front.slots) pos[sl.page] = sl;
    assert (pos[0].row == 1 && pos[0].col == 3 && !pos[0].rotate);
    assert (pos[4].row == 0 && pos[4].col == 0 && pos[4].rotate);
    assert (pos[15].row == 1 && pos[15].col == 2);
    var back = sheets[1];
    var bp = new Gee.HashMap<int, SheetSlot> ();
    foreach (var sl in back.slots) bp[sl.page] = sl;
    assert (bp[1].row == 1 && bp[1].col == 0 && bp[2].col == 3);
    var all = new Gee.HashSet<int> ();
    foreach (var sh in sheets) foreach (var sl in sh.slots) all.add (sl.page);
    assert (all.size == 20);
    assert (sheets[2].slots.size == 2 && sheets[3].slots.size == 2);
    double with_creep = 0;
    foreach (var sl in sheets[2].slots) if (sl.page == 16) with_creep = sl.x;
    o.creep = 0;
    double without = 0;
    var plain = new Exporter (p, o).sheets ();
    foreach (var sl in plain[2].slots) if (sl.page == 16) without = sl.x;
    assert (Math.fabs (with_creep - without - 0.5 * sheets[2].slots[0].scale) < 0.01);
    o.signature = 8;
    var eight = new Exporter (p, o).sheets ();
    assert (eight.size == 6 && eight[0].slots.size == 4);
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-sig-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    try {
        assert (new Exporter (p, o).export_pdf (Path.build_filename (dir, "sig.pdf")) == 6);
    } catch (Error e) {
        error (e.message);
    }
}

void test_interactive_tagged_pdf () {
    var p = doc ();
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 200);
    var st = p.story (t.story);
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text ("Order Form", "Heading 1"));
    st.paras.add (new Paragraph.with_text ("Fill in your name and choose a size.", "Body Text"));
    var name = new ShapeItem (ShapeKind.RECT);
    name.id = p.next_id ();
    name.x = 40;
    name.y = 260;
    name.w = 200;
    name.h = 24;
    name.form = new FormSpec ();
    name.form.kind = FormKind.TEXT;
    name.form.name = "customer";
    name.form.required = true;
    p.pages[0].items.add (name);
    var size = (ShapeItem) name.clone ();
    size.id = p.next_id ();
    size.y = 300;
    size.form.kind = FormKind.CHOICE;
    size.form.name = "size";
    size.form.options = "Small, Medium, Large";
    p.pages[0].items.add (size);
    var next = (ShapeItem) name.clone ();
    next.id = p.next_id ();
    next.y = 340;
    next.form.kind = FormKind.BUTTON;
    next.form.name = "next";
    next.form.action = "page:2";
    p.pages[0].items.add (next);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 260;
    im.y = 260;
    im.w = 60;
    im.h = 60;
    im.alt_text = "Company logo";
    var pbuf = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 8, 8);
    pbuf.fill ((uint32) 0x3366ccffU);
    uint8[] png;
    try {
        pbuf.save_to_buffer (out png, "png");
    } catch (Error e) {
        error (e.message);
    }
    im.media = p.add_media (png, "logo.png");
    p.pages[0].items.add (im);
    p.pages[1].transition = "Dissolve";
    p.pages[1].transition_duration = 2;
    assert (PdfFinish.role_for (p, st.paras[0]) == "H1" && PdfFinish.role_for (p, st.paras[1]) == "P");
    p.styles.find_paragraph ("Body Text").tag = "BlockQuote";
    assert (PdfFinish.role_for (p, st.paras[1]) == "BlockQuote");
    p.styles.find_paragraph ("Body Text").tag = "";
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-ipdf-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string path = Path.build_filename (dir, "form.pdf");
    try {
        assert (new Exporter (p, new ExportOptions ()).export_pdf (path) == 2);
        var d = Singularity.Pdf.Document.open_file (path);
        var fields = Singularity.Pdf.Forms.list (d);
        assert (fields.size == 3);
        var cust = Singularity.Pdf.Forms.find (d, "customer");
        assert (cust != null && cust.type == Singularity.Pdf.FieldType.TEXT && cust.required);
        var sz = Singularity.Pdf.Forms.find (d, "size");
        assert (sz.type == Singularity.Pdf.FieldType.COMBO && sz.options.length == 3);
        var bt = Singularity.Pdf.Forms.find (d, "next");
        assert (bt.type == Singularity.Pdf.FieldType.PUSHBUTTON && bt.widgets[0].dict.has ("A"));
        var w = cust.widgets[0];
        assert (w.page == 0 && Math.fabs (w.rect.x1 - 40) < 0.5 && Math.fabs (w.rect.y2 - (p.settings.height - 260)) < 0.5);
        assert (d.page (1).has ("Trans"));
        var tags = Singularity.Pdf.Tags.read (d);
        var roles = new Gee.HashSet<string> ();
        string alt = "";
        foreach (var n in tags) {
            roles.add (n.role);
            if (n.role == "Figure") alt = n.alt;
        }
        assert (roles.contains ("H1") && roles.contains ("P") && roles.contains ("Figure"));
        var root = d.lookup (d.catalog (), "StructTreeRoot");
        assert (d.lookup (d.lookup (root, "K"), "S").is_name ("Document"));
        assert (alt == "Company logo");
        assert (d.catalog ().has ("MarkInfo") && d.catalog ().has ("Lang"));
    } catch (Error e) {
        error (e.message);
    }
    if (Environment.find_program_in_path ("pdfinfo") != null) {
        string out_s;
        int status;
        try {
            Process.spawn_sync (null, { "pdfinfo", path }, null, SpawnFlags.SEARCH_PATH, null, out out_s, null, out status);
        } catch (Error e) {
            error (e.message);
        }
        string flat = out_s.replace (" ", "");
        assert (flat.contains ("Tagged:yes") && flat.contains ("Form:AcroForm"));
    }
}

void check_xml (string text) {
    try {
        Xml.Doc* d = XmlIn.parse (text);
        delete d;
    } catch (Error e) {
        error ("not well formed: %s\n%s", e.message, text);
    }
}

void test_epub () {
    var p = doc ();
    p.meta.title = "Harbour Guide";
    p.meta.author = "Port Office";
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 300);
    var st = p.story (t.story);
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text ("Arrivals", "Heading 1"));
    var body = new Paragraph.with_text ("Boats & ferries arrive < 9 am", "Body Text");
    body.runs.add (Footnotes.make_run (p, "Except on holidays."));
    st.paras.add (body);
    st.paras.add (new Paragraph.with_text ("Departures", "Heading 1"));
    var li = new Paragraph.with_text ("Bring a ticket", "Body Text");
    li.fmt.list_type = 1;
    st.paras.add (li);
    var im = new ImageFrame ();
    im.id = p.next_id ();
    im.x = 40;
    im.y = 400;
    im.w = 50;
    im.h = 50;
    im.alt_text = "Ferry";
    var pbuf = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 8, 8);
    pbuf.fill ((uint32) 0x3366ccffU);
    uint8[] png;
    try {
        pbuf.save_to_buffer (out png, "png");
    } catch (Error e) {
        error (e.message);
    }
    im.media = p.add_media (png, "ferry.png");
    p.pages[0].items.add (im);
    foreach (bool fixed in new bool[] { false, true }) {
        var e = new EpubExport (p);
        e.fixed_layout = fixed;
        uint8[] data;
        try {
            data = e.build ();
            var z = new ZipReader (data);
            assert (Bin.head (data, 60).contains ("mimetypeapplication/epub+zip"));
            string opf = z.read_text ("OEBPS/content.opf");
            check_xml (opf);
            assert (opf.contains ("<dc:title>Harbour Guide</dc:title>") && opf.contains ("properties=\"nav\"") && opf.contains ("dcterms:modified"));
            check_xml (z.read_text ("OEBPS/nav.xhtml"));
            check_xml (z.read_text ("META-INF/container.xml"));
            assert (opf.contains ("image/png"));
            if (!fixed) {
                string c1 = z.read_text ("OEBPS/chapter1.xhtml");
                string c2 = z.read_text ("OEBPS/chapter2.xhtml");
                check_xml (c1);
                check_xml (c2);
                assert (c1.contains ("<h1") && c1.contains ("Boats &amp; ferries arrive &lt; 9 am") && c1.contains ("epub:type=\"footnote\"") && c1.contains ("Except on holidays."));
                assert (c2.contains ("<ul>") && c2.contains ("<li") && c2.contains ("alt=\"Ferry\""));
                string nav = z.read_text ("OEBPS/nav.xhtml");
                assert (nav.contains ("Arrivals") && nav.contains ("chapter2.xhtml#"));
                assert (z.read_text ("OEBPS/style.css").contains (".s-heading-1{"));
            } else {
                assert (opf.contains ("pre-paginated") && opf.contains ("page%d.xhtml".printf (p.pages.size)));
                string pg = z.read_text ("OEBPS/page1.xhtml");
                check_xml (pg);
                assert (pg.contains ("name=\"viewport\"") && pg.contains ("Departures"));
                assert (z.read_text ("OEBPS/nav.xhtml").contains ("page-list"));
            }
        } catch (Error err) {
            error (err.message);
        }
    }
}

void test_web_site () {
    var p = doc ();
    p.meta.title = "Harbour News";
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 100);
    p.story (t.story).paras[0].runs[0].text = "Welcome aboard";
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-site-%lld".printf (get_monotonic_time ()));
    try {
        assert (WebSite.export (p, dir) == p.pages.size);
        string index, second, map;
        FileUtils.get_contents (Path.build_filename (dir, "index.html"), out index);
        FileUtils.get_contents (Path.build_filename (dir, "page-2.html"), out second);
        FileUtils.get_contents (Path.build_filename (dir, "sitemap.xml"), out map);
        assert (index.contains ("Welcome aboard") && index.contains ("rel=\"next\" href=\"page-2.html\"") && !index.contains ("rel=\"prev\""));
        assert (second.contains ("rel=\"prev\" href=\"index.html\""));
        assert (map.contains ("<loc>index.html</loc>"));
        assert (FileUtils.test (Path.build_filename (dir, "assets", "site.css"), FileTest.EXISTS));
    } catch (Error e) {
        error (e.message);
    }
}

int pdf_images (string path) {
    try {
        var d = Singularity.Pdf.Document.open_file (path);
        d.load_all ();
        int n = 0;
        foreach (var e in d.entries.values) {
            if (e.obj == null || !e.obj.is_stream ()) continue;
            if (d.lookup (e.obj, "Subtype").is_name ("Image")) n++;
        }
        return n;
    } catch (Error e) {
        error (e.message);
    }
}

void test_vector_effects () {
    var p = doc ();
    while (p.pages.size > 1) p.pages.remove_at (1);
    var box = new ShapeItem (ShapeKind.RECT);
    box.id = p.next_id ();
    box.x = 40;
    box.y = 40;
    box.w = 100;
    box.h = 60;
    box.fill = new Fill.solid ("#3366cc");
    box.opacity = 0.6;
    box.shadow.enabled = true;
    box.shadow.blur = 0;
    p.pages[0].items.add (box);
    var t = p.add_text_frame (p.pages[0].items, 40, 200, 200, 40);
    p.story (t.story).paras[0].runs[0].text = "Shadowed headline";
    t.shadow.enabled = true;
    t.shadow.blur = 0;
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-fx-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string sharp = Path.build_filename (dir, "sharp.pdf");
    string soft = Path.build_filename (dir, "soft.pdf");
    try {
        new Exporter (p, new ExportOptions ()).export_pdf (sharp);
        assert (pdf_images (sharp) == 0);
        box.shadow.blur = 6;
        t.shadow.blur = 0;
        new Exporter (p, new ExportOptions ()).export_pdf (soft);
        assert (pdf_images (soft) <= 2);
    } catch (Error e) {
        error (e.message);
    }
    if (Environment.find_program_in_path ("pdftotext") != null) {
        string out_s;
        int status;
        try {
            Process.spawn_sync (null, { "pdftotext", soft, "-" }, null, SpawnFlags.SEARCH_PATH, null, out out_s, null, out status);
        } catch (Error e) {
            error (e.message);
        }
        assert (out_s.contains ("Shadowed headline"));
    }
}

string xlsx_with (string dir, string[,] cells) {
    var sd = new StringBuilder ();
    for (int r = 0; r < cells.length[0]; r++) {
        sd.append ("<row r=\"%d\">".printf (r + 1));
        for (int c = 0; c < cells.length[1]; c++) sd.append ("<c r=\"%c%d\" t=\"inlineStr\"><is><t>%s</t></is></c>".printf ('A' + c, r + 1, Markup.escape_text (cells[r, c])));
        sd.append ("</row>");
    }
    var z = new ZipWriter ();
    string path = Path.build_filename (dir, "prices.xlsx");
    try {
        z.add_text ("[Content_Types].xml", "<Types/>");
        z.add_text ("xl/workbook.xml", "<?xml version=\"1.0\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Prices\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
        z.add_text ("xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\" Type=\"x\"/></Relationships>");
        z.add_text ("xl/worksheets/sheet1.xml", "<?xml version=\"1.0\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>%s</sheetData></worksheet>".printf (sd.str));
        FileUtils.set_data (path, z.finish ());
    } catch (Error e) {
        error (e.message);
    }
    return path;
}

void test_linked_tables () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-link-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string path = xlsx_with (dir, { { "Item", "Price" }, { "Tea", "4" }, { "Cake", "6" } });
    var p = doc ();
    p.base_dir = dir;
    TableItem t;
    try {
        t = LinkedTables.create (p, path, 0, 40, 40, 200);
    } catch (Error e) {
        error (e.message);
    }
    p.pages[0].items.add (t);
    assert (t.rows == 3 && t.cols == 2 && t.cell (2, 0).story.plain_text () == "Cake");
    t.cell (1, 1).fill = "#ffee00";
    t.cell (1, 1).story.paras[0].runs[0].fmt.bold = 1;
    assert (!LinkedTables.modified (p, t));
    Thread.usleep (1100000);
    xlsx_with (dir, { { "Item", "Price" }, { "Tea", "5" }, { "Cake", "6" }, { "Pie", "7" } });
    assert (LinkedTables.modified (p, t));
    assert (LinkedTables.update_all (p) == 1);
    assert (t.rows == 4 && t.cell (1, 1).story.plain_text () == "5" && t.cell (3, 0).story.plain_text () == "Pie");
    assert (t.cell (1, 1).fill == "#ffee00" && t.cell (1, 1).story.paras[0].runs[0].fmt.bold == 1);
    assert (!LinkedTables.modified (p, t));
    var q = round_trip (p);
    var qt = q.find_item (t.id).item as TableItem;
    assert (qt.link_path == path && qt.link_stamp == t.link_stamp);
}

void test_place_vector () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-place-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><rect width=\"200\" height=\"100\" fill=\"#cc2200\"/><circle cx=\"100\" cy=\"50\" r=\"30\" fill=\"#ffffff\"/></svg>";
    string src_pdf = Path.build_filename (dir, "brochure.pdf");
    var ps = new Cairo.PdfSurface (src_pdf, 300, 400);
    var pc = new Cairo.Context (ps);
    pc.select_font_face ("DejaVu Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
    pc.set_font_size (20);
    pc.move_to (40, 60);
    pc.show_text ("First placed page");
    pc.show_page ();
    pc.move_to (40, 60);
    pc.show_text ("Second placed page");
    pc.show_page ();
    ps.finish ();
    var zip = new ZipWriter ();
    uint8[] atl;
    try {
        zip.add_text ("mimetype", "application/x-atelier", false);
        zip.add_text ("project.json", "{}");
        zip.add_text ("sketch/sketch.svg", svg);
        atl = zip.finish ();
    } catch (Error e) {
        error (e.message);
    }
    var p = doc ();
    while (p.pages.size > 1) p.pages.remove_at (1);
    var a = new ImageFrame ();
    a.id = p.next_id ();
    a.x = 20;
    a.y = 20;
    a.w = 200;
    a.h = 100;
    a.fit = FitMode.FIT;
    a.media = p.add_media (svg.data, "logo.svg");
    p.pages[0].items.add (a);
    var b = (ImageFrame) a.clone ();
    b.id = p.next_id ();
    b.y = 140;
    b.w = 150;
    b.h = 200;
    try {
        uint8[] pdfdata;
        FileUtils.get_data (src_pdf, out pdfdata);
        b.media = p.add_media (pdfdata, "brochure.pdf");
    } catch (Error e) {
        error (e.message);
    }
    b.pdf_page = 1;
    p.pages[0].items.add (b);
    var c = (ImageFrame) a.clone ();
    c.id = p.next_id ();
    c.y = 360;
    c.media = p.add_media (atl, "jacket.atelier");
    p.pages[0].items.add (c);
    var store = ImageStore.get_default ();
    var ia = store.info (p, a);
    assert (ia != null && ia.vector && Math.fabs (ia.width * 72.0 / ia.dpi - 150) < 1);
    var art = store.vector (p, b);
    assert (art != null && art.kind == "pdf" && art.pages == 2);
    assert (store.vector (p, c).kind == "atelier");
    string out_pdf = Path.build_filename (dir, "placed.pdf");
    try {
        new Exporter (p, new ExportOptions ()).export_pdf (out_pdf);
    } catch (Error e) {
        error (e.message);
    }
    assert (pdf_images (out_pdf) == 0);
    if (Environment.find_program_in_path ("pdftotext") != null) {
        string out_s;
        int status;
        try {
            Process.spawn_sync (null, { "pdftotext", out_pdf, "-" }, null, SpawnFlags.SEARCH_PATH, null, out out_s, null, out status);
        } catch (Error e) {
            error (e.message);
        }
        assert (out_s.contains ("Second placed page") && !out_s.contains ("First placed page"));
    }
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 300, 450);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_page (cr, 0);
    surf.flush ();
    unowned uint8[] d = surf.get_data ();
    int o = 30 * surf.get_stride () + 40 * 4;
    assert (d[o + 2] > 180 && d[o + 1] < 80);
    int o2 = 370 * surf.get_stride () + 40 * 4;
    assert (d[o2 + 2] > 180 && d[o2 + 1] < 80);
}

void test_review_comments () {
    var p = doc ();
    while (p.pages.size > 1) p.pages.remove_at (1);
    p.settings.set_bleed (0);
    var t = p.add_text_frame (p.pages[0].items, 50, 50, 300, 60);
    t.inset_left = t.inset_right = t.inset_top = t.inset_bottom = 0;
    p.story (t.story).paras[0].runs[0].text = "Harbour opens on Monday";
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-review-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    string pdf = Path.build_filename (dir, "proof.pdf");
    try {
        var o = new ExportOptions ();
        new Exporter (p, o).export_pdf (pdf);
        var d = Singularity.Pdf.Document.open_file (pdf);
        d.load_all ();
        double ph = p.settings.height;
        var note = Singularity.Pdf.Annotations.note (d, 0, 200, ph - 300, "Move the logo up", { 1, 0.8, 0 }, "Editor");
        var cache = new LayoutCache (p);
        var line = cache.story (t.story).frames[0].lines[0];
        int xa, xb;
        line.line ().index_to_x (8, false, out xa);
        line.line ().index_to_x (13, false, out xb);
        double x1 = 50 + line.x + line.x_off + xa / (double) Pango.SCALE, x2 = 50 + line.x + line.x_off + xb / (double) Pango.SCALE;
        double base_y = 50 + line.baseline;
        Singularity.Pdf.Annotations.markup (d, 0, "Highlight", { Singularity.Pdf.Rect.of (x1 + 0.5, ph - base_y - 2, x2 - 0.5, ph - base_y + 8) }, { 1, 1, 0 }, 0.4, "Proofreader", "Check the day");
        var reply = Singularity.Pdf.Annotations.note (d, 0, 210, ph - 300, "Done", { 1, 0.8, 0 }, "Designer");
        d.resolve (reply).set ("IRT", note);
        var so = new Singularity.Pdf.SaveOptions ();
        so.mode = Singularity.Pdf.SaveMode.FULL;
        d.save_to_file (pdf, so);
        assert (Review.import_pdf (p, pdf) == 3);
        assert (p.comments.size == 2);
        ReviewComment? n = null, h = null;
        foreach (var c in p.comments) {
            if (c.kind == "Text") n = c;
            if (c.kind == "Highlight") h = c;
        }
        assert (n != null && n.author == "Editor" && Math.fabs (n.x - 200) < 1 && Math.fabs (n.y - 300) < 1);
        assert (n.replies.size == 1 && n.replies[0].text == "Done");
        assert (h != null && h.quoted == "opens" && h.text == "Check the day");
        assert (Review.import_pdf (p, pdf) == 0);
        var q = round_trip (p);
        assert (q.comments.size == 2 && q.comments[0].replies.size + q.comments[1].replies.size == 1);
    } catch (Error e) {
        error (e.message);
    }
}

void test_linked_story () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-story-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    var p = doc ();
    var special = new ParagraphStyle ("Standfirst", StyleSheet.BASIC);
    special.chars.size = 14;
    p.styles.paragraph.add (special);
    var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 200);
    var st = p.story (t.story);
    st.paras.clear ();
    st.paras.add (new Paragraph.with_text ("Draft opening", "Standfirst"));
    string path = Path.build_filename (dir, "feature.sstory");
    try {
        LinkedStory.export (p, st, path);
        assert (st.link_path == path && !LinkedStory.modified (p, st));
        uint8[] raw;
        FileUtils.get_data (path, out raw);
        assert (FileKind.sniff (raw) == FileKind.STORY && FileKind.from_path (path) == FileKind.STORY);
        string note;
        var writer = Document.load_bytes (raw, path, out note);
        assert (note.contains ("story"));
        TextFrame? wf = null;
        foreach (var it in writer.pages[0].items) if (it is TextFrame) wf = (TextFrame) it;
        var ws = writer.story (wf.story);
        assert (ws.paras[0].style == "Standfirst" && writer.styles.find_paragraph ("Standfirst").chars.size == 14);
        ws.paras[0].runs[0].text = "Final opening";
        ws.paras.add (new Paragraph.with_text ("Second paragraph", "Standfirst"));
        Thread.usleep (1100000);
        FileUtils.set_data (path, Document.serialize (writer, FileKind.STORY));
        assert (LinkedStory.modified (p, st));
        assert (LinkedStory.update_all (p) == 1);
        assert (st.plain_text () == "Final opening\nSecond paragraph" && !LinkedStory.modified (p, st));
        var q = round_trip (p);
        assert (q.story (t.story).link_path == path);
    } catch (Error e) {
        error (e.message);
    }
}

void test_xml_import () {
    var p = doc ();
    var em = new CharacterStyle ("Emphasis");
    em.chars.italic = 1;
    p.styles.character.add (em);
    string xml = """<?xml version="1.0"?>
<catalog>
  <title>Spring Catalogue</title>
  <product id="tea">
    <name>Green Tea</name>
    <desc>Picked in <em>early</em> spring.</desc>
    <image href="tea.jpg" alt="Tea leaves"/>
    <internal>do not print</internal>
  </product>
  <product>
    <name>Cake</name>
    <desc>Baked daily.</desc>
  </product>
</catalog>""";
    try {
        var tags = XmlImport.tags (xml);
        assert (tags.contains ("catalog") && tags.contains ("em") && tags.contains ("image"));
        var imp = new XmlImport (p);
        imp.map["title"] = "Heading 1";
        imp.map["name"] = "Heading 2";
        imp.map["desc"] = "Body Text";
        imp.map["internal"] = XmlImport.IGNORE;
        imp.map["em"] = "char:Emphasis";
        imp.base_dir = "/data";
        imp.auto_map (tags);
        assert (imp.map["em"] == "char:Emphasis" && imp.map["image"] == XmlImport.IMAGE);
        var t = p.add_text_frame (p.pages[0].items, 40, 40, 300, 400);
        var st = p.story (t.story);
        int n = imp.run (xml, st);
        assert (n == 6);
        assert (st.paras[0].style == "Heading 1" && st.paras[0].text () == "Spring Catalogue");
        assert (st.paras[1].style == "Heading 2" && st.paras[1].text () == "Green Tea");
        assert (st.paras[2].text () == "Picked in early spring.");
        bool italic = false;
        foreach (var r in st.paras[2].runs) if (r.text == "early" && r.cstyle == "Emphasis") italic = true;
        assert (italic);
        var img = st.paras[3].runs[0].anchor as ImageFrame;
        assert (img != null && img.link == "/data/tea.jpg" && img.alt_text == "Tea leaves");
        assert (!st.plain_text ().contains ("do not print"));
        var again = new XmlImport (p);
        again.load_map (p.xml_map);
        assert (again.map["internal"] == XmlImport.IGNORE && again.map["desc"] == "Body Text");
        var q = round_trip (p);
        assert (q.xml_map == p.xml_map);
    } catch (Error e) {
        error (e.message);
    }
}

void test_alternate_layouts () {
    var settings = new DocSettings ();
    settings.width = 400;
    settings.height = 600;
    var p = Publication.create (settings, 1);
    var t = p.add_text_frame (p.pages[0].items, 20, 20, 360, 100);
    t.liquid_mode = (int) LiquidMode.OBJECT;
    t.liquid_pins = Liquid.PIN_LEFT | Liquid.PIN_RIGHT | Liquid.PIN_TOP | Liquid.FLEX_W;
    p.story (t.story).paras[0].runs[0].text = "Headline";
    var logo = new ShapeItem (ShapeKind.RECT);
    logo.id = p.next_id ();
    logo.x = 340;
    logo.y = 540;
    logo.w = 40;
    logo.h = 40;
    logo.liquid_mode = (int) LiquidMode.OBJECT;
    logo.liquid_pins = Liquid.PIN_RIGHT | Liquid.PIN_BOTTOM;
    p.pages[0].items.add (logo);
    var photo = new ShapeItem (ShapeKind.RECT);
    photo.id = p.next_id ();
    photo.x = 100;
    photo.y = 200;
    photo.w = 200;
    photo.h = 200;
    p.pages[0].items.add (photo);
    int first = AlternateLayouts.create (p, "", "Landscape", 800, 400);
    assert (first == 1 && p.pages.size == 2 && p.pages[1].layout_name == "Landscape" && p.page_w (1) == 800);
    TextFrame? nt = null;
    ShapeItem? nl = null, nph = null;
    foreach (var it in p.pages[1].items) {
        if (it is TextFrame) nt = (TextFrame) it;
        else if (Math.fabs (it.w - 40) < 0.01) nl = (ShapeItem) it;
        else nph = (ShapeItem) it;
    }
    assert (nt != null && Math.fabs (nt.x - 20) < 0.01 && Math.fabs (nt.w - 760) < 0.01 && Math.fabs (nt.y - 20) < 0.01);
    assert (nl != null && Math.fabs (nl.x - 740) < 0.01 && Math.fabs (nl.y - 340) < 0.01);
    assert (nph != null && Math.fabs (nph.x - 200) < 0.01 && Math.fabs (nph.w - 400) < 0.01 && Math.fabs (nph.h - 133.33) < 0.1);
    var ns = p.story (nt.story);
    assert (ns.id != t.story && ns.source_story == t.story && ns.plain_text () == "Headline");
    p.story (t.story).paras[0].runs[0].text = "New headline";
    assert (AlternateLayouts.update (p) == 1 && ns.plain_text () == "New headline");
    assert (p.sections[p.sections.size - 1].name == "Landscape");
    assert (AlternateLayouts.names (p).contains ("Landscape"));
    var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
    assert (q.pages[1].layout_name == "Landscape" && q.story (nt.story).source_story == t.story);
    var qt = q.find_item (t.id).item;
    assert (qt.liquid_mode == (int) LiquidMode.OBJECT && (qt.liquid_pins & Liquid.FLEX_W) != 0);
}

void test_table_flow () {
    var p = doc ();
    var t = new TableItem (10, 2);
    t.id = p.next_id ();
    t.x = 20;
    t.y = 20;
    t.w = 200;
    t.h = 200;
    t.init_cells (p);
    for (int r = 0; r < 10; r++) {
        t.row_h[r] = 20;
        t.cell (r, 0).story.paras[0].runs[0].text = r == 0 ? "Head" : "Row %d".printf (r);
    }
    t.header_rows = 1;
    t.h = 100;
    p.pages[0].items.add (t);
    var c = new TableItem (0, 0);
    c.id = p.next_id ();
    c.x = 20;
    c.y = 20;
    c.w = 200;
    c.h = 200;
    c.continue_from = t.id;
    t.continue_to = c.id;
    p.pages[1].items.add (c);
    bool overset;
    var parts = TableFlow.assign (p, c, out overset);
    assert (parts.size == 2 && !overset);
    assert (parts[0].size == 5 && parts[0][0] == 0 && parts[0][4] == 4);
    assert (parts[1].size == 6 && parts[1][0] == 0 && parts[1][1] == 5 && parts[1][5] == 9);
    c.h = 80;
    parts = TableFlow.assign (p, t, out overset);
    assert (overset && parts[1].size == 4);
    t.repeat_header = false;
    parts = TableFlow.assign (p, t, out overset);
    assert (parts[1][0] == 5);
    t.repeat_header = true;
    c.h = 200;
    TableItem m;
    var rows = TableFlow.rows_for (p, c, out m, out overset);
    assert (m == t && rows.size == 6 && !overset);
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 300, 300);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    t.header_fill = "#0000ff";
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_page (cr, 1);
    surf.flush ();
    unowned uchar[] data = surf.get_data ();
    int off = 30 * surf.get_stride () + 150 * 4;
    assert (data[off] > 200 && data[off + 2] < 60);
    var q = round_trip (p);
    var qt = (TableItem) q.find_item (t.id).item;
    assert (qt.continue_to == c.id && ((TableItem) q.find_item (c.id).item).continue_from == t.id);
    t.sync_size ();
    assert (t.h == 100);
}

void test_toc () {
    var p = doc ();
    p.add_page (-1, "A");
    for (int pg = 0; pg < 3; pg++) {
        var f = p.add_text_frame (p.pages[pg].items, 40, 40, 400, 600);
        var st = p.story (f.story);
        st.paras.clear ();
        st.paras.add (new Paragraph.with_text ("Chapter %d".printf (pg + 1), "Heading 1"));
        st.paras.add (new Paragraph.with_text ("Body text for the chapter.", "Body Text"));
        if (pg == 1) st.paras.add (new Paragraph.with_text ("A subsection", "Heading 2"));
    }
    var s = new TocSettings ();
    s.title = "Contents";
    s.levels.add (new TocLevel ("Heading 1", 1, Toc.entry_style_for (p, 1)));
    s.levels.add (new TocLevel ("Heading 2", 2, Toc.entry_style_for (p, 2)));
    var tf = p.add_text_frame (p.pages[0].items, 450, 40, 140, 300);
    s.story = tf.story;
    p.toc = s;
    assert (Toc.update (p, s) == 4);
    var st = p.story (tf.story);
    assert (st.paras.size == 5);
    assert (st.paras[0].text () == "Contents");
    assert (st.paras[1].text () == "Chapter 1\t1");
    assert (st.paras[3].text () == "A subsection\t2" && st.paras[3].style == Toc.entry_style_for (p, 2));
    assert (st.paras[4].text () == "Chapter 3\t3");
    assert (TabStop.parse (st.paras[1].fmt.tabs)[0].leader == ".");
    var body = p.story (((TextFrame) p.pages[2].items[0]).story);
    body.paras[0].runs[0].text = "Chapter Three";
    Toc.update (p, s);
    assert (p.story (tf.story).paras[4].text () == "Chapter Three\t3");
    var q = round_trip (p);
    assert (q.toc != null && q.toc.levels.size == 2 && q.toc.story == tf.story && q.toc.title == "Contents");
}

void test_tint_swatches () {
    var p = doc ();
    var spot = new Swatch.cmyk ("Pantone 300", 1, 0.44, 0, 0, true);
    spot.group = "Brand";
    p.swatches.add (spot);
    var tint = spot.clone ();
    tint.name = "Pantone 300 40%";
    tint.tint_of = "Pantone 300";
    tint.tint = 40;
    tint.spot = false;
    p.swatches.add (tint);
    assert (p.canonical (ColorRef.swatch ("Pantone 300 40%")) == ColorRef.swatch ("Pantone 300", 40));
    assert (p.canonical (ColorRef.swatch ("Pantone 300 40%", 50)) == ColorRef.swatch ("Pantone 300", 20));
    var a = p.resolve (ColorRef.swatch ("Pantone 300 40%"));
    var b = p.resolve (ColorRef.swatch ("Pantone 300", 40));
    assert (Math.fabs (a.r - b.r) < 1e-6 && Math.fabs (a.g - b.g) < 1e-6 && Math.fabs (a.b - b.b) < 1e-6);
    var sh = new ShapeItem (ShapeKind.RECT);
    sh.id = p.next_id ();
    sh.fill = new Fill.solid (ColorRef.swatch ("Pantone 300 40%"));
    p.pages[0].items.add (sh);
    assert (p.swatch_in_use ("Pantone 300"));
    var ink = Inks.resolve (p, ColorManager.for_settings (p.settings), ColorRef.swatch ("Pantone 300 40%"));
    assert (ink != null && ink.kind == InkKind.SPOT && ink.spot == "Pantone 300" && Math.fabs (ink.tint - 0.4) < 1e-6);
    var q = round_trip (p);
    var qt = q.swatch ("Pantone 300 40%");
    assert (qt.tint_of == "Pantone 300" && qt.tint == 40 && q.swatch ("Pantone 300").group == "Brand");
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/indesign/style-groups", test_style_groups);
    Test.add_func ("/indesign/object-styles", test_object_styles);
    Test.add_func ("/indesign/grep", test_grep_find_replace);
    Test.add_func ("/indesign/find-objects", test_find_objects);
    Test.add_func ("/indesign/anchored", test_anchored_objects);
    Test.add_func ("/indesign/anchored-wrap", test_anchored_wrap);
    Test.add_func ("/indesign/contour-sources", test_contour_sources);
    Test.add_func ("/indesign/preflight-profiles", test_preflight_profiles);
    Test.add_func ("/indesign/footnotes", test_footnotes);
    Test.add_func ("/indesign/footnote-restart", test_footnote_restart);
    Test.add_func ("/indesign/footnote-split", test_footnote_split);
    Test.add_func ("/indesign/endnotes", test_endnotes);
    Test.add_func ("/indesign/cross-references", test_cross_references);
    Test.add_func ("/indesign/index", test_index);
    Test.add_func ("/indesign/table-styles", test_table_styles);
    Test.add_func ("/indesign/nested-grep-styles", test_nested_grep_styles);
    Test.add_func ("/indesign/optical-margins", test_optical_margins);
    Test.add_func ("/indesign/variable-fonts", test_variable_fonts);
    Test.add_func ("/indesign/rtl-complex-scripts", test_rtl_complex_scripts);
    Test.add_func ("/indesign/mixed-page-sizes", test_mixed_page_sizes);
    Test.add_func ("/indesign/books", test_books);
    Test.add_func ("/indesign/conditional-text", test_conditional_text);
    Test.add_func ("/indesign/separation-preview", test_separation_preview);
    Test.add_func ("/indesign/signatures", test_signatures);
    Test.add_func ("/indesign/interactive-tagged-pdf", test_interactive_tagged_pdf);
    Test.add_func ("/indesign/epub", test_epub);
    Test.add_func ("/indesign/web-site", test_web_site);
    Test.add_func ("/indesign/vector-effects", test_vector_effects);
    Test.add_func ("/indesign/linked-tables", test_linked_tables);
    Test.add_func ("/indesign/place-vector", test_place_vector);
    Test.add_func ("/indesign/review-comments", test_review_comments);
    Test.add_func ("/indesign/linked-story", test_linked_story);
    Test.add_func ("/indesign/xml-import", test_xml_import);
    Test.add_func ("/indesign/alternate-layouts", test_alternate_layouts);
    Test.add_func ("/indesign/table-flow", test_table_flow);
    Test.add_func ("/indesign/toc", test_toc);
    Test.add_func ("/indesign/tint-swatches", test_tint_swatches);
    return Test.run ();
}
