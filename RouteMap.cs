using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.Cache;
using System.Threading;
using System.Windows.Forms;

public sealed class CampusRouteMap : Control
{
    private readonly List<double[]> points = new List<double[]>();
    private readonly Dictionary<string, Image> tiles = new Dictionary<string, Image>();
    private readonly HashSet<string> pending = new HashSet<string>();
    private readonly Dictionary<string, DateTime> failed = new Dictionary<string, DateTime>();
    private readonly Queue<string> tileOrder = new Queue<string>();
    private int zoom = 5;
    private double x, y, dragX, dragY;
    private Point drag;
    private bool dragging;
    private string tileError;
    private bool useGermanTiles = true;
    private int sourceGeneration;
    private double World { get { return 256.0 * (1 << zoom); } }
    public int PointCount { get { return points.Count; } }
    public event EventHandler RouteChanged;

    public void UseGermanTiles(bool enabled)
    {
        if (enabled == useGermanTiles) return;
        useGermanTiles = enabled;
        sourceGeneration++;
        foreach (Image image in tiles.Values) image.Dispose();
        tiles.Clear();
        tileOrder.Clear();
        RetryTiles();
    }

    public void RetryTiles()
    {
        failed.Clear();
        tileError = null;
        Invalidate();
    }

    public CampusRouteMap()
    {
        DoubleBuffered = true;
        BackColor = Color.FromArgb(236, 240, 242);
        MoveTo(35, 105, 5);
    }

    public void MoveTo(double lat, double lon, int level)
    {
        zoom = Math.Max(3, Math.Min(19, level));
        x = WorldX(lon);
        y = WorldY(lat);
        Invalidate();
    }

    public double[][] GetPoints() { return points.ToArray(); }

    public void SetPoints(double[][] route)
    {
        points.Clear();
        if (route != null) points.AddRange(route);
        if (points.Count > 0) MoveTo(points[0][0], points[0][1], 17);
        Changed();
    }

    public void Undo()
    {
        if (points.Count == 0) return;
        points.RemoveAt(points.Count - 1);
        Changed();
    }

    private void Changed()
    {
        Invalidate();
        if (RouteChanged != null) RouteChanged(this, EventArgs.Empty);
    }

    private double WorldX(double lon) { return (lon + 180) / 360 * World; }
    private double WorldY(double lat)
    {
        double radians = Math.Max(-85.05112878, Math.Min(85.05112878, lat)) * Math.PI / 180;
        return (1 - Math.Log(Math.Tan(radians) + 1 / Math.Cos(radians)) / Math.PI) / 2 * World;
    }

    private double Clamp(double value) { return Math.Max(0, Math.Min(World - 0.001, value)); }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        int next = Math.Max(3, Math.Min(19, zoom + Math.Sign(e.Delta)));
        double factor = Math.Pow(2, next - zoom);
        double dx = e.X - Width / 2.0, dy = e.Y - Height / 2.0;
        zoom = next;
        x = Clamp((x + dx) * factor - dx);
        y = Clamp((y + dy) * factor - dy);
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        Focus();
        if (e.Button == MouseButtons.Right)
        {
            dragging = true;
            Capture = true;
            drag = e.Location;
            dragX = x;
            dragY = y;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!dragging) return;
        x = Clamp(dragX + drag.X - e.X);
        y = Clamp(dragY + drag.Y - e.Y);
        Invalidate();
    }

    protected override void OnMouseCaptureChanged(EventArgs e)
    {
        base.OnMouseCaptureChanged(e);
        if (!Capture) dragging = false;
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button == MouseButtons.Right) Capture = false;
        if (e.Button != MouseButtons.Left || zoom < 14 || points.Count >= 9999) return;
        double px = Clamp(x + e.X - Width / 2.0), py = Clamp(y + e.Y - Height / 2.0);
        double lon = px / World * 360 - 180;
        double lat = Math.Atan(Math.Sinh(Math.PI * (1 - 2 * py / World))) * 180 / Math.PI;
        points.Add(new[] { lat, lon });
        Changed();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        double left = x - Width / 2.0, top = y - Height / 2.0;
        int size = 1 << zoom;
        bool drawn = false, unavailable = false;
        for (int row = Math.Max(0, (int)Math.Floor(top / 256)); row < size && row * 256 < top + Height; row++)
        for (int col = Math.Max(0, (int)Math.Floor(left / 256)); col < size && col * 256 < left + Width; col++)
        {
            string key = sourceGeneration + ":" + zoom + "/" + col + "/" + row;
            Image tile;
            if (tiles.TryGetValue(key, out tile))
            {
                e.Graphics.DrawImageUnscaled(tile, (int)(col * 256 - left), (int)(row * 256 - top));
                drawn = true;
            }
            else
            {
                unavailable |= failed.ContainsKey(key);
                RequestTile(key, zoom, col, row);
            }
        }
        if (!drawn)
            TextRenderer.DrawText(e.Graphics, unavailable ? "底图加载失败（" + tileError + "）。检查连接后点「重试底图」。" : "正在加载底图…",
                Font, new Rectangle(0, 0, Width, 36), Color.DimGray, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        if (points.Count == 0) return;
        PointF[] line = points.ConvertAll(p => new PointF((float)(WorldX(p[1]) - left), (float)(WorldY(p[0]) - top))).ToArray();
        using (var pen = new Pen(Color.RoyalBlue, 4))
        {
            if (line.Length > 1) e.Graphics.DrawLines(pen, line);
            foreach (PointF p in line) e.Graphics.FillEllipse(Brushes.RoyalBlue, p.X - 4, p.Y - 4, 8, 8);
            e.Graphics.FillEllipse(Brushes.DarkGreen, line[0].X - 6, line[0].Y - 6, 12, 12);
        }
    }

    private void RequestTile(string key, int level, int column, int row)
    {
        DateTime retry;
        if (pending.Count >= 4 || pending.Contains(key) || (failed.TryGetValue(key, out retry) && retry > DateTime.UtcNow)) return;
        int generation = sourceGeneration;
        string host = useGermanTiles ? "tile.openstreetmap.de" : "tile.openstreetmap.org";
        string url = "https://" + host + "/" + level + "/" + column + "/" + row + ".png";
        pending.Add(key);
        ThreadPool.QueueUserWorkItem(delegate
        {
            Image tile = null;
            string error = null;
            try
            {
                var request = (HttpWebRequest)WebRequest.Create(url);
                request.UserAgent = "CampusRunLab-RouteMap/1.0";
                request.CachePolicy = new HttpRequestCachePolicy(HttpRequestCacheLevel.Default);
                request.Timeout = 7000;
                request.ReadWriteTimeout = 7000;
                using (var response = request.GetResponse())
                using (var stream = response.GetResponseStream())
                using (var image = Image.FromStream(stream)) tile = new Bitmap(image);
            }
            catch (WebException ex)
            {
                using (var response = ex.Response as HttpWebResponse)
                    error = response == null ? ex.Status.ToString() : "HTTP " + (int)response.StatusCode;
            }
            catch (IOException) { error = "读取失败"; }
            catch (ArgumentException) { error = "返回内容不是地图图片"; }
            try
            {
                Invoke((Action)delegate
                {
                    pending.Remove(key);
                    if (generation != sourceGeneration)
                    {
                        if (tile != null) tile.Dispose();
                        Invalidate();
                        return;
                    }
                    if (tile == null)
                    {
                        failed[key] = DateTime.UtcNow.AddSeconds(20);
                        tileError = error;
                    }
                    else
                    {
                        failed.Remove(key);
                        tiles.Add(key, tile);
                        tileOrder.Enqueue(key);
                        if (tileOrder.Count > 96)
                        {
                            string old = tileOrder.Dequeue();
                            tiles[old].Dispose();
                            tiles.Remove(old);
                        }
                    }
                    Invalidate();
                });
            }
            catch (InvalidOperationException) { if (tile != null) tile.Dispose(); }
        });
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) foreach (Image tile in tiles.Values) tile.Dispose();
        base.Dispose(disposing);
    }
}
