using Singularity.Apps.Publish;

string out_dir () {
    string? d = Environment.get_variable ("PUBLISH_TEST_OUT");
    if (d == null || d == "") d = Environment.get_tmp_dir ();
    DirUtils.create_with_parents (d, 0755);
    return d;
}

int expected_pages (string id) {
    switch (id) {
        case "brochure":
        case "business-cards":
        case "greeting-card":
        case "postcard":
            return 2;
        case "newsletter":
        case "program":
            return 4;
        case "calendar":
            return 12;
        default:
            return 1;
    }
}

bool fonts_installed (Publication p) {
    foreach (string f in p.used_fonts ()) {
        if (!Preflight.system_has_font (f)) return false;
    }
    return true;
}

void check_no_overset (Publication p, string id) {
    if (!fonts_installed (p)) printerr ("%s: template fonts are not all installed, fitting is checked with the substitutes the user sees\n", id);
    var cache = new LayoutCache (p);
    foreach (var s in p.stories.values) {
        var frames = p.thread_frames (s.id);
        if (frames.size == 0) continue;
        var r = p.find_item (frames[0].id);
        StoryResult res;
        if (r != null && r.master != null) {
            for (int i = 0; i < p.pages.size; i++) {
                res = cache.master_story (s.id, i);
                if (res.overset) {
                    printerr ("%s: master story %d overset on page %d by %d characters: %s\n", id, s.id, i, res.overset_chars, s.plain_text ());
                    failures++;
                }
            }
            continue;
        }
        res = cache.story (s.id);
        if (res.overset) {
            printerr ("%s: story %d overset by %d characters: %s\n", id, s.id, res.overset_chars, s.plain_text ().substring (0, int.min (80, s.plain_text ().length)));
            failures++;
        }
    }
    var pf = new Preflight (p);
    pf.font_check = (f) => true;
    foreach (var issue in pf.run ()) {
        if (issue.kind == IssueKind.OVERSET || issue.kind == IssueKind.OUTSIDE_BLEED) {
            var r = p.find_item (issue.item);
            printerr ("%s: page %d %s %s\n", id, issue.page, issue.message, r != null ? "%s %.0f,%.0f %.0fx%.0f".printf (r.item.name, r.item.x, r.item.y, r.item.w, r.item.h) : "");
            failures++;
        }
    }
}

void test_catalogue () {
    var list = Templates.all ();
    assert (list.size == 20);
    var ids = new Gee.HashSet<string> ();
    foreach (var t in list) {
        assert (t.name != "" && t.description != "" && t.category != "");
        assert (!ids.contains (t.id));
        ids.add (t.id);
        assert (Templates.find (t.id) != null);
    }
    assert (Templates.find ("missing") == null);
}

int failures = 0;

void test_build_all () {
    failures = 0;
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        assert (p.pages.size == expected_pages (t.id));
        assert (p.layers.size >= 1);
        assert (p.masters.size >= 1);
        int items = 0;
        foreach (var pg in p.pages) items += pg.items.size;
        items += p.masters[0].items.size;
        assert (items >= 5);
        foreach (var s in p.stories.values) foreach (int fid in s.frames) {
            var r = p.find_item (fid);
            assert (r != null && r.item is TextFrame && ((TextFrame) r.item).story == s.id);
        }
        check_no_overset (p, t.id);
    }
    assert (failures == 0);
}

void test_masters () {
    foreach (string id in new string[] { "newsletter", "program", "letterhead" }) {
        var p = Templates.build (id);
        assert (p.masters[0].items.size > 0);
        if (p.settings.facing) assert (p.masters[0].left_items.size > 0);
    }
    var n = Templates.build ("newsletter");
    assert (n.settings.facing);
    assert (n.pages[0].hide_master);
    assert (!n.pages[1].hide_master);
    bool page_field = false;
    foreach (var s in n.stories.values) if (s.fields ().contains (Fields.PAGE)) page_field = true;
    assert (page_field);
    var threaded = false;
    foreach (var s in n.stories.values) {
        if (s.frames.size < 2) continue;
        var a = n.find_item (s.frames[0]);
        var z = n.find_item (s.frames[s.frames.size - 1]);
        if (a.page != z.page) threaded = true;
    }
    assert (threaded);
    var b = Templates.blank (new DocSettings (), 3);
    assert (b.pages.size == 3);
    assert (b.masters[0].items.size > 0);
}

void test_specifics () {
    var cards = Templates.build ("business-cards");
    assert (cards.settings.impose == "nup:2x5:a4");
    assert (Math.fabs (cards.settings.width - 85 * Units.PT_PER_MM) < 0.1);
    assert (cards.settings.bleed_top > 0);
    var menu = Templates.build ("menu");
    bool leaders = false;
    foreach (var ps in menu.styles.paragraph) {
        foreach (var t in TabStop.parse (ps.para.tabs)) if (t.leader == "." && t.kind == TabKind.RIGHT) leaders = true;
    }
    assert (leaders);
    var prog = Templates.build ("program");
    bool table = false;
    foreach (var it in prog.pages[2].items) if (it is TableItem) table = true;
    assert (table);
    var cert = Templates.build ("certificate");
    assert (cert.settings.landscape ());
    var news = Templates.build ("newsletter");
    bool drop = false;
    foreach (var ps in news.styles.paragraph) if (ps.para.drop_lines >= 2) drop = true;
    assert (drop);
    bool wrap = false;
    news.walk ((r) => {
        if (r.item.wrap != WrapMode.NONE) wrap = true;
        return true;
    });
    assert (wrap);
    var bro = Templates.build ("brochure");
    assert (bro.settings.columns == 3 && bro.pages[0].guides.size == 2);
    var inherit = news.styles.find_paragraph ("News Lead");
    assert (inherit != null && inherit.based_on == "News Body");
    var pf = new ParaFormat ();
    var cf = CharFormat.defaults ();
    news.styles.resolve_paragraph ("News Lead", pf, cf);
    assert (cf.font == "DejaVu Serif" && pf.drop_lines == 3);
}

void test_round_trip () {
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        Publication q;
        try {
            q = NativeFormat.from_xml (NativeFormat.to_xml (p));
        } catch (Error e) {
            printerr ("%s: %s\n", t.id, e.message);
            assert_not_reached ();
        }
        assert (q.pages.size == p.pages.size);
        for (int i = 0; i < p.pages.size; i++) assert (q.pages[i].items.size == p.pages[i].items.size);
        assert (q.masters[0].items.size == p.masters[0].items.size);
        assert (q.stories.size == p.stories.size);
        foreach (var s in p.stories.values) {
            assert (q.stories.has_key (s.id));
            assert (q.stories[s.id].plain_text () == s.plain_text ());
            assert (q.stories[s.id].frames.size == s.frames.size);
        }
        assert (q.swatches.size == p.swatches.size);
        assert (q.styles.paragraph.size == p.styles.paragraph.size);
        assert (q.settings.impose == p.settings.impose);
    }
}

void test_render () {
    string dir = out_dir ();
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        var ex = new Exporter (p);
        var thumb = ex.thumbnail (0, 640);
        assert (thumb.write_to_png (Path.build_filename (dir, "tpl-%s.png".printf (t.id))) == Cairo.Status.SUCCESS);
        for (int i = 1; i < p.pages.size; i++) {
            var other = ex.thumbnail (i, 640);
            assert (other.write_to_png (Path.build_filename (dir, "tpl-%s-%d.png".printf (t.id, i + 1))) == Cairo.Status.SUCCESS);
        }
        thumb.flush ();
        unowned uint8[] data = thumb.get_data ();
        bool non_white = false;
        int total = thumb.get_stride () * thumb.get_height ();
        for (int i = 0; i < total; i++) if (i % 4 != 3 && data[i] < 200) {
            non_white = true;
            break;
        }
        assert (non_white);
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/templates/catalogue", test_catalogue);
    Test.add_func ("/templates/build", test_build_all);
    Test.add_func ("/templates/masters", test_masters);
    Test.add_func ("/templates/specifics", test_specifics);
    Test.add_func ("/templates/round-trip", test_round_trip);
    Test.add_func ("/templates/render", test_render);
    return Test.run ();
}
