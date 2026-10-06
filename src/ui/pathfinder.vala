namespace Singularity.Apps.Publish {

    public class Pathfinder {
        public static Cairo.Matrix matrix_of (Item it) {
            var m = Cairo.Matrix.identity ();
            m.translate (it.x + it.w / 2, it.y + it.h / 2);
            if (it.rotation != 0) m.rotate (it.rotation * Math.PI / 180);
            m.scale (it.flip_h ? -1 : 1, it.flip_v ? -1 : 1);
            m.translate (-it.w / 2, -it.h / 2);
            return m;
        }

        public static Singularity.Vector.PathData? local_path (Item it) {
            var s = it as ShapeItem;
            if (s != null && s.shape == ShapeKind.PATH && s.path_d != "") {
                var p = Singularity.Vector.PathData.parse_svg (s.path_d);
                var sc = Cairo.Matrix.identity ();
                sc.scale (it.w, it.h);
                return p.transformed (sc);
            }
            if ((s != null && s.shape == ShapeKind.ELLIPSE) || it.shape_ellipse) return new Singularity.Vector.PathData.ellipse (it.w / 2, it.h / 2, it.w / 2, it.h / 2);
            if (s != null && s.shape != ShapeKind.RECT) {
                if (s.shape == ShapeKind.LINE || (s.shape == ShapeKind.PATH && !s.closed)) return null;
                var pts = s.local_points ();
                if (pts.size < 3) return null;
                var p = new Singularity.Vector.PathData ();
                p.move_to (pts[0].x, pts[0].y);
                for (int i = 1; i < pts.size; i++) p.line_to (pts[i].x, pts[i].y);
                p.close ();
                return p;
            }
            if (it.corner == CornerKind.ROUNDED && it.corner_radius > 0) return new Singularity.Vector.PathData.round_rect (0, 0, it.w, it.h, it.corner_radius);
            if (it is TextFrame || it is ImageFrame || s != null) return new Singularity.Vector.PathData.rect (0, 0, it.w, it.h);
            return null;
        }

        public static Singularity.Vector.PathData? page_path (Item it) {
            var p = local_path (it);
            if (p == null) return null;
            return p.transformed (matrix_of (it));
        }

        public static ShapeItem? from_path (Publication pub, Singularity.Vector.PathData path, Item style_from) {
            if (path.is_empty ()) return null;
            var b = path.bounds ();
            double w = double.max (0.5, b.w), h = double.max (0.5, b.h);
            var norm = Cairo.Matrix.identity ();
            norm.scale (1 / w, 1 / h);
            norm.translate (-b.x, -b.y);
            var s = new ShapeItem (ShapeKind.PATH);
            s.id = pub.next_id ();
            s.layer = style_from.layer;
            s.x = b.x;
            s.y = b.y;
            s.w = w;
            s.h = h;
            s.path_d = path.transformed (norm).to_svg (6);
            s.closed = true;
            s.even_odd = true;
            s.fill = style_from.fill.clone ();
            s.stroke = style_from.stroke.clone ();
            s.opacity = style_from.opacity;
            return s;
        }

        public static ShapeItem? combine (Publication pub, Gee.List<Item> items, Singularity.Vector.BoolOp op) {
            var paths = new Gee.ArrayList<Singularity.Vector.PathData> ();
            Item? first = null;
            foreach (var it in items) {
                var p = page_path (it);
                if (p == null) continue;
                paths.add (p);
                if (first == null) first = it;
            }
            if (paths.size < 2) return null;
            Singularity.Vector.PathData result;
            if (op == Singularity.Vector.BoolOp.SUBTRACT) {
                result = paths[0];
                for (int i = 1; i < paths.size; i++) result = Singularity.Vector.CurveBoolean.apply (result, paths[i], op);
            } else {
                result = Singularity.Vector.CurveBoolean.combine (paths, op);
            }
            return from_path (pub, result, first);
        }

        public static ShapeItem? convert_to_path (Publication pub, Item it) {
            var p = page_path (it);
            if (p == null) return null;
            var s = from_path (pub, p, it);
            if (s != null) s.even_odd = false;
            return s;
        }
    }
}
