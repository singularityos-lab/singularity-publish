namespace Singularity.Apps.Publish {

    public enum ItemKind {
        TEXT,
        IMAGE,
        SHAPE,
        TABLE,
        GROUP;

        public string to_string () {
            switch (this) {
                case IMAGE: return "image";
                case SHAPE: return "shape";
                case TABLE: return "table";
                case GROUP: return "group";
                default: return "text";
            }
        }
    }

    public enum FillKind {
        NONE,
        SOLID,
        LINEAR,
        RADIAL,
        PATTERN,
        TEXTURE,
        PICTURE;

        public string to_string () {
            switch (this) {
                case SOLID: return "solid";
                case LINEAR: return "linear";
                case RADIAL: return "radial";
                case PATTERN: return "pattern";
                case TEXTURE: return "texture";
                case PICTURE: return "picture";
                default: return "none";
            }
        }

        public static FillKind parse (string s) {
            switch (s) {
                case "solid": return SOLID;
                case "linear": return LINEAR;
                case "radial": return RADIAL;
                case "pattern": return PATTERN;
                case "texture": return TEXTURE;
                case "picture": return PICTURE;
                default: return NONE;
            }
        }
    }

    public class GradientStop {
        public double offset;
        public string color;
        public double opacity;

        public GradientStop (double offset, string color, double opacity = 1) {
            this.offset = offset;
            this.color = color;
            this.opacity = opacity;
        }
    }

    public class Fill {
        public FillKind kind = FillKind.NONE;
        public string color = ColorRef.NONE;
        public double angle = 90;
        public Gee.ArrayList<GradientStop> stops = new Gee.ArrayList<GradientStop> ();
        public string pattern = "";
        public string bg_color = ColorRef.PAPER;
        public string texture = "";
        public string media = "";
        public string link = "";
        public bool tile = false;
        public double tile_scale = 1;

        public Fill () {
        }

        public Fill.solid (string color) {
            kind = color == ColorRef.NONE ? FillKind.NONE : FillKind.SOLID;
            this.color = color;
        }

        public Fill.linear (string a, string b, double angle = 90) {
            kind = FillKind.LINEAR;
            this.angle = angle;
            color = a;
            stops.add (new GradientStop (0, a));
            stops.add (new GradientStop (1, b));
        }

        public Fill clone () {
            var f = new Fill ();
            f.kind = kind;
            f.color = color;
            f.angle = angle;
            foreach (var s in stops) f.stops.add (new GradientStop (s.offset, s.color, s.opacity));
            f.pattern = pattern;
            f.bg_color = bg_color;
            f.texture = texture;
            f.media = media;
            f.link = link;
            f.tile = tile;
            f.tile_scale = tile_scale;
            return f;
        }

        public bool visible () {
            return kind != FillKind.NONE && (kind != FillKind.SOLID || color != ColorRef.NONE);
        }

        public Gee.ArrayList<string> colors () {
            var l = new Gee.ArrayList<string> ();
            if (kind == FillKind.SOLID) l.add (color);
            else if (kind == FillKind.PATTERN) {
                l.add (color);
                if (bg_color != ColorRef.NONE) l.add (bg_color);
            } else if (kind == FillKind.LINEAR || kind == FillKind.RADIAL) foreach (var s in stops) l.add (s.color);
            return l;
        }
    }

    public enum DashKind {
        SOLID,
        DASH,
        DOT,
        DASH_DOT
    }

    public class Stroke {
        public string color = ColorRef.NONE;
        public double width = 1;
        public DashKind dash = DashKind.SOLID;
        public int cap = 0;
        public int join = 0;
        public int arrow_start = 0;
        public int arrow_end = 0;

        public Stroke () {
        }

        public Stroke.with (string color, double width) {
            this.color = color;
            this.width = width;
        }

        public bool visible () {
            return color != ColorRef.NONE && width > 0;
        }

        public Stroke clone () {
            var s = new Stroke.with (color, width);
            s.dash = dash;
            s.cap = cap;
            s.join = join;
            s.arrow_start = arrow_start;
            s.arrow_end = arrow_end;
            return s;
        }
    }

    public class Shadow {
        public bool enabled = false;
        public double dx = 3;
        public double dy = 3;
        public double blur = 6;
        public string color = ColorRef.BLACK;
        public double opacity = 0.35;

        public Shadow clone () {
            var s = new Shadow ();
            s.enabled = enabled;
            s.dx = dx;
            s.dy = dy;
            s.blur = blur;
            s.color = color;
            s.opacity = opacity;
            return s;
        }
    }

    public enum CornerKind {
        NONE,
        ROUNDED,
        BEVEL,
        INSET,
        INVERSE_ROUNDED
    }

    public enum WrapMode {
        NONE,
        BOUNDING_BOX,
        CONTOUR,
        JUMP,
        THROUGH,
        BEHIND,
        IN_FRONT;

        public string to_string () {
            switch (this) {
                case BOUNDING_BOX: return "box";
                case CONTOUR: return "contour";
                case JUMP: return "jump";
                case THROUGH: return "through";
                case BEHIND: return "behind";
                case IN_FRONT: return "front";
                default: return "none";
            }
        }

        public static WrapMode parse (string s) {
            switch (s) {
                case "box": return BOUNDING_BOX;
                case "contour": return CONTOUR;
                case "jump": return JUMP;
                case "through": return THROUGH;
                case "behind": return BEHIND;
                case "front": return IN_FRONT;
                default: return NONE;
            }
        }

        public bool wraps () {
            return this == BOUNDING_BOX || this == CONTOUR || this == JUMP || this == THROUGH;
        }
    }

    public enum WrapSide {
        BOTH,
        LARGEST,
        LEFT,
        RIGHT
    }

    public enum FitMode {
        FILL,
        FIT,
        STRETCH,
        MANUAL;

        public string to_string () {
            switch (this) {
                case FIT: return "fit";
                case STRETCH: return "stretch";
                case MANUAL: return "manual";
                default: return "fill";
            }
        }

        public static FitMode parse (string s) {
            switch (s) {
                case "fit": return FIT;
                case "stretch": return STRETCH;
                case "manual": return MANUAL;
                default: return FILL;
            }
        }
    }

    public enum ShapeKind {
        RECT,
        ELLIPSE,
        POLYGON,
        STAR,
        LINE,
        PATH,
        WORDART;

        public string to_string () {
            switch (this) {
                case ELLIPSE: return "ellipse";
                case POLYGON: return "polygon";
                case STAR: return "star";
                case LINE: return "line";
                case PATH: return "path";
                case WORDART: return "wordart";
                default: return "rect";
            }
        }

        public static ShapeKind parse (string s) {
            switch (s) {
                case "ellipse": return ELLIPSE;
                case "polygon": return POLYGON;
                case "star": return STAR;
                case "line": return LINE;
                case "path": return PATH;
                case "wordart": return WORDART;
                default: return RECT;
            }
        }

        public string label () {
            switch (this) {
                case ELLIPSE: return _("Ellipse");
                case POLYGON: return _("Polygon");
                case STAR: return _("Star");
                case LINE: return _("Line");
                case PATH: return _("Path");
                case WORDART: return _("WordArt");
                default: return _("Rectangle");
            }
        }
    }

    public struct Point {
        public double x;
        public double y;

        public Point (double x, double y) {
            this.x = x;
            this.y = y;
        }
    }

    public abstract class Item {
        public int id;
        public string name = "";
        public double x;
        public double y;
        public double w;
        public double h;
        public double rotation = 0;
        public bool flip_h = false;
        public bool flip_v = false;
        public int layer = 0;
        public bool locked = false;
        public bool hidden = false;
        public bool nonprinting = false;
        public Fill fill = new Fill ();
        public Stroke stroke = new Stroke ();
        public double opacity = 1;
        public Shadow shadow = new Shadow ();
        public CornerKind corner = CornerKind.NONE;
        public double corner_radius = 0;
        public WrapMode wrap = WrapMode.NONE;
        public double wrap_offset = 6;
        public WrapSide wrap_side = WrapSide.BOTH;
        public bool shape_ellipse = false;
        public string alt_text = "";
        public bool alt_decorative = false;
        public string link = "";
        public bool overprint_fill = false;
        public bool overprint_stroke = false;
        public Gee.ArrayList<Point?> wrap_points = new Gee.ArrayList<Point?> ();
        public Effects effects = new Effects ();
        public BorderArt border_art = new BorderArt ();
        public string object_style = "";
        public MergeFilter? show_when = null;
        public FormSpec? form = null;
        public int liquid_mode = 0;
        public int liquid_pins = 0;

        public abstract ItemKind kind { get; }

        public abstract Item clone ();

        protected void copy_base (Item o) {
            o.id = id;
            o.name = name;
            o.x = x;
            o.y = y;
            o.w = w;
            o.h = h;
            o.rotation = rotation;
            o.flip_h = flip_h;
            o.flip_v = flip_v;
            o.layer = layer;
            o.locked = locked;
            o.hidden = hidden;
            o.nonprinting = nonprinting;
            o.fill = fill.clone ();
            o.stroke = stroke.clone ();
            o.opacity = opacity;
            o.shadow = shadow.clone ();
            o.corner = corner;
            o.corner_radius = corner_radius;
            o.wrap = wrap;
            o.wrap_offset = wrap_offset;
            o.wrap_side = wrap_side;
            o.shape_ellipse = shape_ellipse;
            o.alt_text = alt_text;
            o.alt_decorative = alt_decorative;
            o.link = link;
            o.overprint_fill = overprint_fill;
            o.overprint_stroke = overprint_stroke;
            o.wrap_points.clear ();
            foreach (var p in wrap_points) o.wrap_points.add (p);
            o.effects = effects.clone ();
            o.border_art = border_art.clone ();
            o.object_style = object_style;
            o.show_when = show_when != null ? show_when.clone () : null;
            o.form = form != null ? form.clone () : null;
            o.liquid_mode = liquid_mode;
            o.liquid_pins = liquid_pins;
        }

        public Gee.ArrayList<Point?> wrap_outline () {
            if (wrap_points.size < 3) return outline ();
            var pts = new Gee.ArrayList<Point?> ();
            foreach (var p in wrap_points) pts.add (to_page (p.x * w, p.y * h));
            return pts;
        }

        public Rect box () {
            return Rect (x, y, w, h);
        }

        public Point center () {
            return Point (x + w / 2, y + h / 2);
        }

        public Point to_page (double lx, double ly) {
            double cx = x + w / 2, cy = y + h / 2;
            double dx = lx - w / 2, dy = ly - h / 2;
            if (flip_h) dx = -dx;
            if (flip_v) dy = -dy;
            double a = rotation * Math.PI / 180;
            double c = Math.cos (a), s = Math.sin (a);
            return Point (cx + dx * c - dy * s, cy + dx * s + dy * c);
        }

        public Point to_local (double px, double py) {
            double cx = x + w / 2, cy = y + h / 2;
            double a = -rotation * Math.PI / 180;
            double c = Math.cos (a), s = Math.sin (a);
            double dx = px - cx, dy = py - cy;
            double lx = dx * c - dy * s, ly = dx * s + dy * c;
            if (flip_h) lx = -lx;
            if (flip_v) ly = -ly;
            return Point (lx + w / 2, ly + h / 2);
        }

        public Rect bounds () {
            if (rotation == 0) return box ();
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            double[] xs = { 0, w, w, 0 };
            double[] ys = { 0, 0, h, h };
            for (int i = 0; i < 4; i++) {
                var p = to_page (xs[i], ys[i]);
                minx = double.min (minx, p.x);
                miny = double.min (miny, p.y);
                maxx = double.max (maxx, p.x);
                maxy = double.max (maxy, p.y);
            }
            return Rect (minx, miny, maxx - minx, maxy - miny);
        }

        public virtual Gee.ArrayList<Point?> outline () {
            var pts = new Gee.ArrayList<Point?> ();
            if (shape_ellipse) {
                for (int i = 0; i < 48; i++) {
                    double t = 2 * Math.PI * i / 48;
                    pts.add (to_page (w / 2 + w / 2 * Math.cos (t), h / 2 + h / 2 * Math.sin (t)));
                }
                return pts;
            }
            pts.add (to_page (0, 0));
            pts.add (to_page (w, 0));
            pts.add (to_page (w, h));
            pts.add (to_page (0, h));
            return pts;
        }

        public bool hit (double px, double py, double tolerance = 0) {
            var l = to_local (px, py);
            return l.x >= -tolerance && l.y >= -tolerance && l.x <= w + tolerance && l.y <= h + tolerance;
        }

        public virtual Gee.ArrayList<string> colors () {
            var l = fill.colors ();
            if (stroke.visible ()) l.add (stroke.color);
            if (shadow.enabled) l.add (shadow.color);
            if (effects.glow) l.add (effects.glow_color);
            if (border_art.visible () && border_art.color != ColorRef.NONE) l.add (border_art.color);
            return l;
        }

        public string kind_label () {
            switch (kind) {
                case ItemKind.TEXT: return _("Text Frame");
                case ItemKind.IMAGE: return _("Image Frame");
                case ItemKind.TABLE: return _("Table");
                case ItemKind.GROUP: return _("Group");
                default: return ((ShapeItem) this).shape.label ();
            }
        }
    }

    public class TextFrame : Item {
        public int story = 0;
        public int columns = 1;
        public double gutter = 12;
        public double inset_top = 0;
        public double inset_right = 0;
        public double inset_bottom = 0;
        public double inset_left = 0;
        public int valign = 0;
        public bool ignore_wrap = false;
        public bool auto_height = false;
        public int autofit = 0;
        public bool vertical = false;
        public bool own_grid = false;
        public double grid_start = 0;
        public double grid_step = 12;
        public string grid_color = "#99c2f2";

        public override ItemKind kind {
            get { return ItemKind.TEXT; }
        }

        public override Item clone () {
            var t = new TextFrame ();
            copy_base (t);
            t.story = story;
            t.columns = columns;
            t.gutter = gutter;
            t.inset_top = inset_top;
            t.inset_right = inset_right;
            t.inset_bottom = inset_bottom;
            t.inset_left = inset_left;
            t.valign = valign;
            t.ignore_wrap = ignore_wrap;
            t.auto_height = auto_height;
            t.autofit = autofit;
            t.vertical = vertical;
            t.own_grid = own_grid;
            t.grid_start = grid_start;
            t.grid_step = grid_step;
            t.grid_color = grid_color;
            return t;
        }
    }

    public class ImageFrame : Item {
        public string link = "";
        public string media = "";
        public FitMode fit = FitMode.FILL;
        public double img_x = 0;
        public double img_y = 0;
        public double img_scale = 1;
        public double focus_x = 0.5;
        public double focus_y = 0.5;
        public string merge_field = "";
        public string link_stamp = "";
        public double brightness = 0;
        public double contrast = 0;
        public int recolor = 0;
        public string recolor_color = "swatch:Blue";
        public string transparent_color = "";
        public string clip_shape = "";
        public int clip_sides = 5;
        public double clip_inset = 0.5;
        public int contour_source = 0;
        public bool clip_path = false;
        public int pdf_page = 0;

        public override ItemKind kind {
            get { return ItemKind.IMAGE; }
        }

        public bool adjusted () {
            return Math.fabs (brightness) > 0.001 || Math.fabs (contrast) > 0.001 || recolor != 0 || transparent_color != "";
        }

        public bool has_image () {
            return link != "" || media != "";
        }

        public override Item clone () {
            var t = new ImageFrame ();
            copy_base (t);
            t.link = link;
            t.media = media;
            t.fit = fit;
            t.img_x = img_x;
            t.img_y = img_y;
            t.img_scale = img_scale;
            t.focus_x = focus_x;
            t.focus_y = focus_y;
            t.merge_field = merge_field;
            t.link_stamp = link_stamp;
            t.brightness = brightness;
            t.contrast = contrast;
            t.recolor = recolor;
            t.recolor_color = recolor_color;
            t.transparent_color = transparent_color;
            t.clip_shape = clip_shape;
            t.clip_sides = clip_sides;
            t.clip_inset = clip_inset;
            t.contour_source = contour_source;
            t.clip_path = clip_path;
            t.pdf_page = pdf_page;
            return t;
        }
    }

    public class ShapeItem : Item {
        public ShapeKind shape = ShapeKind.RECT;
        public int sides = 6;
        public double star_inset = 0.5;
        public bool line_reverse = false;
        public Gee.ArrayList<Point?> points = new Gee.ArrayList<Point?> ();
        public bool closed = true;
        public string path_d = "";
        public bool even_odd = false;

        public ShapeItem (ShapeKind shape) {
            this.shape = shape;
            shape_ellipse = shape == ShapeKind.ELLIPSE;
        }

        public override ItemKind kind {
            get { return ItemKind.SHAPE; }
        }

        protected void copy_shape (ShapeItem t) {
            copy_base (t);
            t.sides = sides;
            t.star_inset = star_inset;
            t.line_reverse = line_reverse;
            t.closed = closed;
            t.path_d = path_d;
            t.even_odd = even_odd;
            foreach (var p in points) t.points.add (p);
        }

        public override Item clone () {
            var t = new ShapeItem (shape);
            copy_base (t);
            t.sides = sides;
            t.star_inset = star_inset;
            t.line_reverse = line_reverse;
            t.closed = closed;
            t.path_d = path_d;
            t.even_odd = even_odd;
            foreach (var p in points) t.points.add (p);
            return t;
        }

        public Gee.ArrayList<Point?> local_points () {
            if (shape == ShapeKind.PATH && path_d != "") return SvgPath.flatten (path_d, w, h);
            var pts = new Gee.ArrayList<Point?> ();
            switch (shape) {
                case ShapeKind.POLYGON:
                    int n = int.max (3, sides);
                    for (int i = 0; i < n; i++) {
                        double t = -Math.PI / 2 + 2 * Math.PI * i / n;
                        pts.add (Point (w / 2 + w / 2 * Math.cos (t), h / 2 + h / 2 * Math.sin (t)));
                    }
                    break;
                case ShapeKind.STAR:
                    int n = int.max (3, sides);
                    for (int i = 0; i < n * 2; i++) {
                        double t = -Math.PI / 2 + Math.PI * i / n;
                        double f = i % 2 == 0 ? 1 : star_inset.clamp (0.05, 1);
                        pts.add (Point (w / 2 + w / 2 * f * Math.cos (t), h / 2 + h / 2 * f * Math.sin (t)));
                    }
                    break;
                case ShapeKind.LINE:
                    if (line_reverse) {
                        pts.add (Point (0, h));
                        pts.add (Point (w, 0));
                    } else {
                        pts.add (Point (0, 0));
                        pts.add (Point (w, h));
                    }
                    break;
                case ShapeKind.PATH:
                    foreach (var p in points) pts.add (Point (p.x * w, p.y * h));
                    break;
                default:
                    pts.add (Point (0, 0));
                    pts.add (Point (w, 0));
                    pts.add (Point (w, h));
                    pts.add (Point (0, h));
                    break;
            }
            return pts;
        }

        public override Gee.ArrayList<Point?> outline () {
            if (shape == ShapeKind.ELLIPSE || shape == ShapeKind.RECT) return base.outline ();
            var pts = new Gee.ArrayList<Point?> ();
            foreach (var p in local_points ()) pts.add (to_page (p.x, p.y));
            return pts;
        }
    }

    public enum WarpKind {
        NONE,
        ARCH_UP,
        ARCH_DOWN,
        CIRCLE,
        WAVE,
        INFLATE,
        DEFLATE,
        SLANT_UP,
        SLANT_DOWN,
        TRIANGLE_UP,
        FADE_RIGHT,
        CASCADE;

        public string to_string () {
            switch (this) {
                case ARCH_UP: return "arch-up";
                case ARCH_DOWN: return "arch-down";
                case CIRCLE: return "circle";
                case WAVE: return "wave";
                case INFLATE: return "inflate";
                case DEFLATE: return "deflate";
                case SLANT_UP: return "slant-up";
                case SLANT_DOWN: return "slant-down";
                case TRIANGLE_UP: return "triangle-up";
                case FADE_RIGHT: return "fade-right";
                case CASCADE: return "cascade";
                default: return "none";
            }
        }

        public static WarpKind parse (string s) {
            foreach (var k in all ()) if (k.to_string () == s) return k;
            return NONE;
        }

        public static WarpKind[] all () {
            return { NONE, ARCH_UP, ARCH_DOWN, CIRCLE, WAVE, INFLATE, DEFLATE, SLANT_UP, SLANT_DOWN, TRIANGLE_UP, FADE_RIGHT, CASCADE };
        }

        public string label () {
            switch (this) {
                case ARCH_UP: return _("Arch Up");
                case ARCH_DOWN: return _("Arch Down");
                case CIRCLE: return _("Circle");
                case WAVE: return _("Wave");
                case INFLATE: return _("Inflate");
                case DEFLATE: return _("Deflate");
                case SLANT_UP: return _("Slant Up");
                case SLANT_DOWN: return _("Slant Down");
                case TRIANGLE_UP: return _("Triangle");
                case FADE_RIGHT: return _("Fade Right");
                case CASCADE: return _("Cascade Up");
                default: return _("Plain");
            }
        }
    }

    public class WordArtItem : ShapeItem {
        public string text = "";
        public string font = "Inter";
        public bool bold = true;
        public bool italic = false;
        public WarpKind warp = WarpKind.NONE;
        public double warp_amount = 0.5;
        public bool even_height = false;

        public WordArtItem () {
            base (ShapeKind.WORDART);
        }

        public override Item clone () {
            var t = new WordArtItem ();
            copy_shape (t);
            t.text = text;
            t.font = font;
            t.bold = bold;
            t.italic = italic;
            t.warp = warp;
            t.warp_amount = warp_amount;
            t.even_height = even_height;
            return t;
        }
    }

    public class Cell {
        public Story story;
        public string fill = ColorRef.NONE;
        public int row_span = 1;
        public int col_span = 1;
        public bool covered = false;
        public int valign = 0;
        public int diagonal = 0;
        public string cell_style = "";

        public Cell (int story_id) {
            story = new Story (story_id);
        }

        public Cell clone () {
            var c = new Cell (story.id);
            c.story = story.clone ();
            c.fill = fill;
            c.row_span = row_span;
            c.col_span = col_span;
            c.covered = covered;
            c.valign = valign;
            c.diagonal = diagonal;
            c.cell_style = cell_style;
            return c;
        }
    }

    public class TableItem : Item {
        public int rows;
        public int cols;
        public Gee.ArrayList<double?> col_w = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> row_h = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<Gee.ArrayList<Cell>> cells = new Gee.ArrayList<Gee.ArrayList<Cell>> ();
        public int header_rows = 1;
        public string border_color = ColorRef.BLACK;
        public double border_width = 0.5;
        public string header_fill = ColorRef.NONE;
        public string alt_fill = ColorRef.NONE;
        public double cell_inset = 4;
        public int continue_to = 0;
        public int continue_from = 0;
        public bool repeat_header = true;
        public string table_style = "";
        public string link_path = "";
        public int link_sheet = 0;
        public string link_stamp = "";

        public bool flows () {
            return continue_to != 0 || continue_from != 0;
        }

        public TableItem (int rows, int cols) {
            this.rows = rows;
            this.cols = cols;
        }

        public override ItemKind kind {
            get { return ItemKind.TABLE; }
        }

        public void init_cells (Publication pub) {
            cells.clear ();
            for (int r = 0; r < rows; r++) {
                var row = new Gee.ArrayList<Cell> ();
                for (int c = 0; c < cols; c++) row.add (new Cell (pub.next_id ()));
                cells.add (row);
            }
            col_w.clear ();
            row_h.clear ();
            for (int c = 0; c < cols; c++) col_w.add (w / cols);
            for (int r = 0; r < rows; r++) row_h.add (h / rows);
        }

        public Cell cell (int r, int c) {
            return cells[r][c];
        }

        public override Item clone () {
            var t = new TableItem (rows, cols);
            copy_base (t);
            foreach (var v in col_w) t.col_w.add (v);
            foreach (var v in row_h) t.row_h.add (v);
            foreach (var row in cells) {
                var nr = new Gee.ArrayList<Cell> ();
                foreach (var c in row) nr.add (c.clone ());
                t.cells.add (nr);
            }
            t.header_rows = header_rows;
            t.border_color = border_color;
            t.border_width = border_width;
            t.header_fill = header_fill;
            t.alt_fill = alt_fill;
            t.cell_inset = cell_inset;
            t.continue_to = continue_to;
            t.continue_from = continue_from;
            t.repeat_header = repeat_header;
            t.table_style = table_style;
            t.link_path = link_path;
            t.link_sheet = link_sheet;
            t.link_stamp = link_stamp;
            return t;
        }

        public double col_x (int c) {
            double v = 0;
            for (int i = 0; i < c && i < col_w.size; i++) v += col_w[i];
            return v;
        }

        public double row_y (int r) {
            double v = 0;
            for (int i = 0; i < r && i < row_h.size; i++) v += row_h[i];
            return v;
        }

        public void sync_size () {
            double tw = 0, th = 0;
            foreach (var v in col_w) tw += v;
            foreach (var v in row_h) th += v;
            w = tw;
            if (!flows ()) h = th;
        }

        public void scale_to (double nw, double nh) {
            if (flows ()) {
                double sw = 0;
                foreach (var v in col_w) sw += v;
                if (sw > 0) for (int i = 0; i < col_w.size; i++) col_w[i] = col_w[i] * nw / sw;
                w = nw;
                h = nh;
                return;
            }
            double tw = 0, th = 0;
            foreach (var v in col_w) tw += v;
            foreach (var v in row_h) th += v;
            if (tw > 0) for (int i = 0; i < col_w.size; i++) col_w[i] = col_w[i] * nw / tw;
            if (th > 0) for (int i = 0; i < row_h.size; i++) row_h[i] = row_h[i] * nh / th;
            w = nw;
            h = nh;
        }

        public void insert_row (Publication pub, int at) {
            var row = new Gee.ArrayList<Cell> ();
            for (int c = 0; c < cols; c++) row.add (new Cell (pub.next_id ()));
            cells.insert (at, row);
            row_h.insert (at, rows > 0 ? row_h[int.min (at, rows - 1)] : 20);
            rows++;
            sync_size ();
        }

        public void insert_col (Publication pub, int at) {
            foreach (var row in cells) row.insert (at, new Cell (pub.next_id ()));
            col_w.insert (at, cols > 0 ? col_w[int.min (at, cols - 1)] : 60);
            cols++;
            sync_size ();
        }

        public void delete_row (int at) {
            if (rows <= 1) return;
            cells.remove_at (at);
            row_h.remove_at (at);
            rows--;
            unmerge_all ();
            sync_size ();
        }

        public void delete_col (int at) {
            if (cols <= 1) return;
            foreach (var row in cells) row.remove_at (at);
            col_w.remove_at (at);
            cols--;
            unmerge_all ();
            sync_size ();
        }

        public void unmerge_all () {
            foreach (var row in cells) foreach (var c in row) {
                c.row_span = 1;
                c.col_span = 1;
                c.covered = false;
            }
        }

        public void merge (int r1, int c1, int r2, int c2) {
            int ra = int.min (r1, r2), rb = int.max (r1, r2), ca = int.min (c1, c2), cb = int.max (c1, c2);
            for (int r = ra; r <= rb; r++) for (int c = ca; c <= cb; c++) {
                var cell = cells[r][c];
                if (r == ra && c == ca) continue;
                if (!cell.story.is_empty ()) {
                    var head = cells[ra][ca].story;
                    head.insert_story (head.end_pos (), cell.story);
                }
                cell.covered = true;
                cell.story = new Story (cell.story.id);
            }
            cells[ra][ca].row_span = rb - ra + 1;
            cells[ra][ca].col_span = cb - ca + 1;
        }

        public void split (int r, int c) {
            var cell = cells[r][c];
            for (int i = r; i < r + cell.row_span && i < rows; i++) for (int j = c; j < c + cell.col_span && j < cols; j++) cells[i][j].covered = false;
            cell.row_span = 1;
            cell.col_span = 1;
        }

        public override Gee.ArrayList<string> colors () {
            var l = base.colors ();
            l.add (border_color);
            if (header_fill != ColorRef.NONE) l.add (header_fill);
            if (alt_fill != ColorRef.NONE) l.add (alt_fill);
            foreach (var row in cells) foreach (var c in row) if (c.fill != ColorRef.NONE) l.add (c.fill);
            return l;
        }
    }

    public class GroupItem : Item {
        public Gee.ArrayList<Item> children = new Gee.ArrayList<Item> ();

        public override ItemKind kind {
            get { return ItemKind.GROUP; }
        }

        public override Item clone () {
            var g = new GroupItem ();
            copy_base (g);
            foreach (var c in children) g.children.add (c.clone ());
            return g;
        }

        public void fit_children () {
            if (children.size == 0) return;
            Rect r = children[0].bounds ();
            foreach (var c in children) r = r.union (c.bounds ());
            x = r.x;
            y = r.y;
            w = r.w;
            h = r.h;
        }

        public void move_by (double dx, double dy) {
            x += dx;
            y += dy;
            foreach (var c in children) {
                var g = c as GroupItem;
                if (g != null) g.move_by (dx, dy);
                else {
                    c.x += dx;
                    c.y += dy;
                }
            }
        }

        public void scale_children (Rect from, Rect to) {
            double sx = from.w > 0 ? to.w / from.w : 1, sy = from.h > 0 ? to.h / from.h : 1;
            foreach (var c in children) {
                var g = c as GroupItem;
                var old = c.box ();
                var nb = Rect (to.x + (old.x - from.x) * sx, to.y + (old.y - from.y) * sy, old.w * sx, old.h * sy);
                if (g != null) {
                    g.scale_children (old, nb);
                } else if (c is TableItem) {
                    ((TableItem) c).scale_to (nb.w, nb.h);
                }
                c.x = nb.x;
                c.y = nb.y;
                c.w = nb.w;
                c.h = nb.h;
            }
        }

        public override Gee.ArrayList<string> colors () {
            var l = base.colors ();
            foreach (var c in children) l.add_all (c.colors ());
            return l;
        }
    }
}
