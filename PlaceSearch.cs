using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Net;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public sealed class CampusPlaceSearch : Form {
    private readonly TextBox query = new TextBox();
    private readonly Button search = new Button();
    private readonly Button choose = new Button();
    private readonly ListBox results = new ListBox();
    private readonly Label status = new Label();
    private readonly CampusRouteMap map;
    private sealed class Place {
        public string Name; public double Lat; public double Lon;
        public override string ToString() { return Name; }
    }
    public CampusPlaceSearch(CampusRouteMap target) {
        map = target; Text = "地名搜索"; StartPosition = FormStartPosition.CenterParent;
        ClientSize = new Size(620, 390); MinimumSize = new Size(520, 350);
        Font = new Font("Microsoft YaHei UI", 10);
        query.SetBounds(15, 15, 475, 28); query.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        search.Text = "搜索"; search.SetBounds(500, 13, 100, 31); search.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        results.SetBounds(15, 56, 585, 230); results.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        status.SetBounds(15, 296, 470, 62); status.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
        status.Text = "输入城市、学校或地名后点击搜索。搜索需联网，服务可能因网络不可用。";
        choose.Text = "定位选中地点"; choose.SetBounds(490, 305, 110, 40); choose.Anchor = AnchorStyles.Bottom | AnchorStyles.Right; choose.Enabled = false;
        Controls.AddRange(new Control[] {query,search,results,status,choose}); AcceptButton=search;
        search.Click += async delegate { await SearchAsync(); };
        results.SelectedIndexChanged += delegate { choose.Enabled = results.SelectedItem is Place; };
        results.DoubleClick += delegate { SelectPlace(); }; choose.Click += delegate { SelectPlace(); };
    }
    private void SelectPlace() {
        var p=results.SelectedItem as Place; if(p==null)return;
        map.MoveTo(p.Lat,p.Lon,17); DialogResult=DialogResult.OK; Close();
    }
    private async Task SearchAsync() {
        string q=query.Text.Trim(); if(q.Length<2){status.Text="请输入至少两个字或字符。";return;}
        search.Enabled=false; choose.Enabled=false; results.Items.Clear(); status.Text="正在搜索，请稍候……";
        try {
            string url="https://photon.komoot.io/api/?limit=6&q="+Uri.EscapeDataString(q);
            string json;
            using(var client=new WebClient()) {
                client.Headers[HttpRequestHeader.UserAgent]="CampusRunLab/1.0 (route editor)";
                var task=client.DownloadStringTaskAsync(new Uri(url));
                if(await Task.WhenAny(task,Task.Delay(10000))!=task){client.CancelAsync();throw new TimeoutException();}
                json=await task;
            }
            if(IsDisposed)return;
            var root=new JavaScriptSerializer().DeserializeObject(json) as IDictionary<string,object>;
            var features=root==null?null:root["features"] as object[];
            if(features!=null)foreach(object obj in features){
                var f=obj as IDictionary<string,object>; if(f==null)continue;
                var geometry=f["geometry"] as IDictionary<string,object>; var props=f["properties"] as IDictionary<string,object>;
                var coords=geometry==null?null:geometry["coordinates"] as object[]; if(coords==null || coords.Length<2 || props==null)continue;
                double lon=Convert.ToDouble(coords[0],CultureInfo.InvariantCulture),lat=Convert.ToDouble(coords[1],CultureInfo.InvariantCulture);
                if(double.IsNaN(lat)||double.IsInfinity(lat)||double.IsNaN(lon)||double.IsInfinity(lon)||Math.Abs(lat)>85||Math.Abs(lon)>180)continue;
                var parts=new List<string>(); foreach(string key in new[]{"name","city","state","country"}){object value;if(props.TryGetValue(key,out value)&&value!=null&&!parts.Contains(value.ToString()))parts.Add(value.ToString());}
                if(parts.Count>0)results.Items.Add(new Place{Name=string.Join("，",parts.ToArray()),Lat=lat,Lon=lon});
            }
            status.Text=results.Items.Count==0?"没有找到结果，请加上城市名或使用经纬度定位。":"请选择结果，再点击“定位选中地点”。数据 © OpenStreetMap contributors";
        } catch(Exception) { if(!IsDisposed)status.Text="搜索未能完成。请检查网络，或使用地图窗口中的经纬度定位。"; }
        finally { if(!IsDisposed)search.Enabled=true; }
    }
}
