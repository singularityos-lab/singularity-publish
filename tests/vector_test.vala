using Singularity.Apps.Publish;

ShapeItem box (Publication p, double x, double y, double w, double h, ShapeKind k = ShapeKind.RECT) {
    var s = new ShapeItem (k);
    s.id = p.next_id ();
    s.x = x;
    s.y = y;
    s.w = w;
    s.h = h;
    s.fill = new Fill.solid ("#ff0000");
    return s;
}

uint8 red_at (Publication p, Item it, int x, int y) {
    var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, 300, 300);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (1, 1, 1);
    cr.paint ();
    var r = new Renderer (p);
    r.opts.print = true;
    r.draw_item (cr, it, false, 0);
    surf.flush ();
    unowned uint8[] d = surf.get_data ();
    return d[y * surf.get_stride () + x * 4 + 1];
}

void test_pathfinder () {
    var p = Publication.create (null, 1);
    var a = box (p, 10, 10, 100, 100);
    var b = box (p, 60, 60, 100, 100, ShapeKind.ELLIPSE);
    var items = new Gee.ArrayList<Item> ();
    items.add (a);
    items.add (b);
    var u = Pathfinder.combine (p, items, Singularity.Vector.BoolOp.UNION);
    assert (u != null && u.shape == ShapeKind.PATH && u.path_d.contains ("C"));
    assert (Math.fabs (u.x - 10) < 0.5 && Math.fabs (u.w - 150) < 0.5);
    assert (red_at (p, u, 20, 20) < 50 && red_at (p, u, 150, 110) < 50 && red_at (p, u, 150, 20) > 200);
    var sub = Pathfinder.combine (p, items, Singularity.Vector.BoolOp.SUBTRACT);
    assert (red_at (p, sub, 20, 20) < 50 && red_at (p, sub, 100, 100) > 200);
    var inter = Pathfinder.combine (p, items, Singularity.Vector.BoolOp.INTERSECT);
    assert (red_at (p, inter, 100, 100) < 50 && red_at (p, inter, 20, 20) > 200);
    var ex = Pathfinder.combine (p, items, Singularity.Vector.BoolOp.EXCLUDE);
    assert (red_at (p, ex, 20, 20) < 50 && red_at (p, ex, 100, 100) > 200 && red_at (p, ex, 150, 110) < 50);
    var star = box (p, 0, 0, 100, 100, ShapeKind.STAR);
    var sp = Pathfinder.convert_to_path (p, star);
    assert (sp != null && sp.local_points ().size >= 10);
    p.pages[0].items.add (u);
    var q = NativeFormat.from_xml (NativeFormat.to_xml (p));
    var qu = q.find_item (u.id).item as ShapeItem;
    assert (qu.path_d == u.path_d && qu.even_odd);
    var bd = SvgPath.bezier_d (new Gee.ArrayList<Point?>.wrap ({ Point (0, 0), Point (100, 0) }), new Gee.ArrayList<Point?>.wrap ({ Point (0, 50), Point (0, -50) }), false, 0, -50, 100, 100);
    assert (bd == "M 0 0.5 C 0 1 1 1 1 0.5");
    var curve = box (p, 0, 0, 100, 100, ShapeKind.PATH);
    curve.path_d = bd;
    curve.closed = false;
    curve.fill = new Fill ();
    curve.stroke = new Stroke.with ("#ff0000", 4);
    assert (red_at (p, curve, 50, 87) < 60 && red_at (p, curve, 50, 50) > 200);
    assert (SvgPath.smooth (new Gee.ArrayList<Point?>.wrap ({ Point (0, 0), Point (1, 0), Point (1, 1) }), false).has_prefix ("M 0 0 C"));
}

void test_suite_library () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "publish-assets-%lld".printf (get_monotonic_time ()));
    DirUtils.create_with_parents (dir, 0700);
    var lib = new Singularity.Assets.AssetLibrary (Path.build_filename (dir, "assets.json"));
    var p = Publication.create (null, 1);
    var gold = new Swatch.cmyk ("Gold", 0, 0.2, 0.8, 0.1, true);
    p.swatches.add (gold);
    var head = new ParagraphStyle ("Brand Head", StyleSheet.BASIC);
    head.chars.size = 30;
    head.chars.font = "DejaVu Serif";
    p.styles.paragraph.add (head);
    var t = p.add_text_frame (p.pages[0].items, 10, 10, 200, 50);
    p.story (t.story).paras[0].runs[0].text = "Logo text";
    p.story (t.story).paras[0].style = "Brand Head";
    var mark = box (p, 220, 10, 40, 40, ShapeKind.ELLIPSE);
    mark.fill = new Fill.solid (ColorRef.swatch ("Gold"));
    p.pages[0].items.add (mark);
    var items = new Gee.ArrayList<Item> ();
    items.add (t);
    items.add (mark);
    try {
        lib.add (SuiteAssets.from_swatch (gold));
        lib.add (SuiteAssets.from_paragraph_style (p, head));
        lib.add (SuiteAssets.from_items (p, "Signature", items));
        lib.save ();
        var other = new Singularity.Assets.AssetLibrary (Path.build_filename (dir, "assets.json"));
        assert (other.list ("color").size == 1 && other.list ("paragraph-style").size == 1 && other.list ("block").size == 1);
        var q = Publication.create (null, 1);
        var sw = SuiteAssets.to_swatch (other.list ("color")[0]);
        assert (sw.spot && Math.fabs (sw.m - 0.2) < 1e-6 && sw.name == "Gold");
        assert (other.list ("color")[0].get_field ("color").has_prefix ("#"));
        assert (SuiteAssets.import_styles (q, other.list ("paragraph-style")[0]) >= 1);
        assert (q.styles.find_paragraph ("Brand Head").chars.size == 30);
        var made = SuiteAssets.place (q, other.list ("block")[0], q.pages[0].items);
        assert (made.size == 2 && q.swatch ("Gold") != null);
        var mt = made[0] as TextFrame;
        assert (mt != null && q.story (mt.story).plain_text () == "Logo text");
        var ids = new Gee.HashSet<int> ();
        q.walk ((r) => {
            assert (ids.add (r.item.id));
            return true;
        });
    } catch (Error e) {
        error (e.message);
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/vector/pathfinder", test_pathfinder);
    Test.add_func ("/vector/suite-library", test_suite_library);
    return Test.run ();
}
