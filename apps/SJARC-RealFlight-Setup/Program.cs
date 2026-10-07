using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("SJ-ARC RealFlight Setup")]
[assembly: AssemblyDescription("Unofficial educational MFE VTOL setup assistant. No automatic ARM or flight.")]
[assembly: AssemblyVersion("0.2.2.0")]

namespace SJARC {
    static class Program {
        [STAThread] static void Main(string[] args) {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            string work = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SJARC", "RealFlightSetup", "0.1.0");
            for (int i=0;i+1<args.Length;i++) if (args[i]=="--work-root") work=Path.GetFullPath(args[i+1]);
            try { Application.Run(new SetupForm(work)); }
            catch(Exception ex) { MessageBox.Show(ex.Message, "SJ-ARC 실행 오류", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }
    sealed class ModelChoice {
        public string Key, Title;
        public override string ToString() { return Title; }
    }
    static class Theme {
        public static readonly Color Page=Color.FromArgb(243,245,248), Card=Color.White, Line=Color.FromArgb(223,228,234),
            Text=Color.FromArgb(23,32,45), Muted=Color.FromArgb(96,108,122), Faint=Color.FromArgb(160,168,178),
            Accent=Color.FromArgb(35,79,132), AccentSoft=Color.FromArgb(229,238,249), AccentText=Color.FromArgb(22,62,110),
            Good=Color.FromArgb(36,121,83), GoodSoft=Color.FromArgb(226,243,234), Warn=Color.FromArgb(166,104,0), WarnSoft=Color.FromArgb(252,242,222),
            Bad=Color.FromArgb(176,42,42), Hover=Color.FromArgb(238,242,247);
        public static GraphicsPath Round(Rectangle r,int radius) {
            var p=new GraphicsPath(); int d=Math.Max(1,Math.Min(radius*2,Math.Min(r.Width,r.Height)));
            p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90); p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90);
            p.CloseFigure(); return p;
        }
    }
    // Left-rail step. Owner-drawn so the state marks stay crisp and need no symbol font.
    sealed class StepButton : Control {
        public const int Pending=0, Current=1, Done=2, Attention=3, Utility=4;
        int mark; bool selected, hover;
        public StepButton(string caption,int mark) {
            Text=caption; this.mark=mark; Dock=DockStyle.Top; Cursor=Cursors.Hand; TabStop=true;
            SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw|ControlStyles.UserPaint,true);
        }
        public int Mark { get {return mark;} set {if(mark!=value){mark=value;Invalidate();}} }
        public bool Selected { get {return selected;} set {if(selected!=value){selected=value;Invalidate();}} }
        protected override void OnMouseEnter(EventArgs e) {hover=true;Invalidate();base.OnMouseEnter(e);}
        protected override void OnMouseLeave(EventArgs e) {hover=false;Invalidate();base.OnMouseLeave(e);}
        protected override void OnGotFocus(EventArgs e) {Invalidate();base.OnGotFocus(e);}
        protected override void OnLostFocus(EventArgs e) {Invalidate();base.OnLostFocus(e);}
        protected override void OnKeyDown(KeyEventArgs e) {if(e.KeyCode==Keys.Enter||e.KeyCode==Keys.Space)OnClick(EventArgs.Empty);base.OnKeyDown(e);}
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics; g.SmoothingMode=SmoothingMode.AntiAlias;
            g.Clear(Parent==null?Theme.Card:Parent.BackColor);
            var box=new Rectangle(0,2,Width-1,Height-5);
            if(selected||hover) using(var b=new SolidBrush(selected?Theme.AccentSoft:Theme.Hover)) using(var p=Theme.Round(box,6)) g.FillPath(b,p);
            if(Focused&&ShowFocusCues&&!selected) using(var pen=new Pen(Theme.Accent)) using(var p=Theme.Round(box,6)) g.DrawPath(pen,p);
            int d=Math.Max(14,Height/2-2); var c=new Rectangle(Height/4,(Height-d)/2,d,d);
            DrawMark(g,c);
            using(var font=new Font(Font,selected?FontStyle.Bold:FontStyle.Regular))
                TextRenderer.DrawText(g,Text,font,new Rectangle(c.Right+Height/4,0,Width-c.Right-Height/4,Height),selected?Theme.AccentText:(mark==Pending?Theme.Muted:Theme.Text),TextFormatFlags.VerticalCenter|TextFormatFlags.Left|TextFormatFlags.EndEllipsis);
        }
        void DrawMark(Graphics g,Rectangle c) {
            float w=Math.Max(1.6f,c.Width/8f);
            if(mark==Done) {
                using(var b=new SolidBrush(Theme.Good)) g.FillEllipse(b,c);
                using(var p=new Pen(Color.White,w) {StartCap=LineCap.Round,EndCap=LineCap.Round,LineJoin=LineJoin.Round})
                    g.DrawLines(p,new[]{new PointF(c.X+c.Width*0.28f,c.Y+c.Height*0.53f),new PointF(c.X+c.Width*0.44f,c.Y+c.Height*0.68f),new PointF(c.X+c.Width*0.73f,c.Y+c.Height*0.36f)});
            } else if(mark==Current) {
                using(var p=new Pen(Theme.Accent,w)) g.DrawEllipse(p,c.X+w/2,c.Y+w/2,c.Width-w,c.Height-w);
                using(var b=new SolidBrush(Theme.Accent)) g.FillEllipse(b,c.X+c.Width*0.3f,c.Y+c.Height*0.3f,c.Width*0.4f,c.Height*0.4f);
            } else if(mark==Attention) {
                using(var b=new SolidBrush(Theme.Warn)) g.FillEllipse(b,c);
                using(var p=new Pen(Color.White,w) {StartCap=LineCap.Round,EndCap=LineCap.Round}) g.DrawLine(p,c.X+c.Width/2f,c.Y+c.Height*0.24f,c.X+c.Width/2f,c.Y+c.Height*0.56f);
                using(var b=new SolidBrush(Color.White)) g.FillEllipse(b,c.X+c.Width/2f-w*0.65f,c.Y+c.Height*0.68f,w*1.3f,w*1.3f);
            } else if(mark==Utility) {
                using(var p=new Pen(Theme.Muted,w) {StartCap=LineCap.Round,EndCap=LineCap.Round})
                    foreach(float y in new[]{0.32f,0.5f,0.68f}) g.DrawLine(p,c.X+c.Width*0.22f,c.Y+c.Height*y,c.X+c.Width*(y>0.6f?0.6f:0.78f),c.Y+c.Height*y);
            } else {
                using(var p=new Pen(Theme.Faint,w)) g.DrawEllipse(p,c.X+w/2,c.Y+w/2,c.Width-w,c.Height-w);
            }
        }
    }
    // Status-strip entry: coloured dot plus a short label.
    sealed class StatusItem : Control {
        Color dot=Theme.Faint;
        public StatusItem(string text) {
            Text=text; Margin=new Padding(0,0,18,0);
            SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw|ControlStyles.UserPaint,true);
            Fit();
        }
        public void Set(Color color,string text) {dot=color;Text=text;Fit();Invalidate();}
        void Fit() {var s=TextRenderer.MeasureText(Text,Font);Size=new Size(s.Width+s.Height,s.Height+8);}
        protected override void OnFontChanged(EventArgs e) {Fit();base.OnFontChanged(e);}
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics; g.SmoothingMode=SmoothingMode.AntiAlias; g.Clear(Parent==null?Theme.Card:Parent.BackColor);
            int d=Math.Max(8,Height/3); using(var b=new SolidBrush(dot)) g.FillEllipse(b,1,(Height-d)/2,d,d);
            TextRenderer.DrawText(g,Text,Font,new Rectangle(d+7,0,Width-d-7,Height),Theme.Muted,TextFormatFlags.VerticalCenter|TextFormatFlags.Left|TextFormatFlags.NoPadding);
        }
    }
    // Connection map for the SITL step: controller -> RealFlight <-> ArduPilot SITL <-> Mission Planner.
    // Drawn in a 780 x 158 design space and scaled to the control, so fonts are pixel-sized to avoid double DPI scaling.
    sealed class ConnectionDiagram : Control {
        public ConnectionDiagram() {
            SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw|ControlStyles.UserPaint,true);
        }
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics; g.SmoothingMode=SmoothingMode.AntiAlias; g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.Clear(Parent==null?Theme.Card:Parent.BackColor);
            const float W=780f,H=158f;
            float s=Math.Min(Width/W,Height/H); if(s<=0f) return;
            g.TranslateTransform(Math.Max(0f,(Width-W*s)/2f),0f); g.ScaleTransform(s,s);
            using(var title=new Font(Font.FontFamily,14f,FontStyle.Bold,GraphicsUnit.Pixel))
            using(var body=new Font(Font.FontFamily,12f,FontStyle.Regular,GraphicsUnit.Pixel))
            using(var bold=new Font(Font.FontFamily,12f,FontStyle.Bold,GraphicsUnit.Pixel))
            using(var small=new Font(Font.FontFamily,11f,FontStyle.Regular,GraphicsUnit.Pixel)) {
                Box(g,new RectangleF(40,4,150,30),Theme.Hover,Theme.Line,null,"조종기 (TX16S · 조이스틱)",title,body);
                Arrow(g,115,35,115,56,false); Write(g,"USB",small,Theme.Muted,new RectangleF(121,36,60,18),false);
                Box(g,new RectangleF(10,58,190,62),Theme.AccentSoft,Theme.Accent,"RealFlight","기체 물리 · 화면 · 조종기 읽기",title,body);
                Box(g,new RectangleF(295,58,190,62),Theme.AccentSoft,Theme.Accent,"ArduPilot SITL","비행 제어 (ArduPlane)",title,body);
                Box(g,new RectangleF(580,58,190,62),Theme.AccentSoft,Theme.Accent,"Mission Planner","지상국 · 파라미터 · 모드",title,body);
                Arrow(g,204,89,291,89,true);
                Write(g,"FlightAxis",bold,Theme.Text,new RectangleF(200,64,95,18),true); Write(g,"TCP 18083",body,Theme.Muted,new RectangleF(200,96,95,18),true);
                Arrow(g,489,89,576,89,true);
                Write(g,"MAVLink",bold,Theme.Text,new RectangleF(485,64,95,18),true); Write(g,"TCP 5760",body,Theme.Muted,new RectangleF(485,96,95,16),true); Write(g,"UDP 14550",body,Theme.Muted,new RectangleF(485,111,95,16),true);
                Write(g,"기체 상태 ↔ 모터·서보 출력",small,Theme.Muted,new RectangleF(140,134,215,18),true);
                Write(g,"화면 · 파라미터 · 모드 (둘 중 하나로 연결)",small,Theme.Muted,new RectangleF(412,134,240,18),true);
            }
        }
        static void Box(Graphics g,RectangleF r,Color fill,Color line,string title,string body,Font titleFont,Font bodyFont) {
            var rect=Rectangle.Round(r);
            using(var path=Theme.Round(rect,6)) {using(var b=new SolidBrush(fill)) g.FillPath(b,path); using(var p=new Pen(line)) g.DrawPath(p,path);}
            if(title==null) {Write(g,body,bodyFont,Theme.Text,r,true);return;}
            Write(g,title,titleFont,Theme.AccentText,new RectangleF(r.X,r.Y+8,r.Width,22),true);
            Write(g,body,bodyFont,Theme.Muted,new RectangleF(r.X,r.Y+33,r.Width,20),true);
        }
        static void Write(Graphics g,string text,Font font,Color color,RectangleF r,bool center) {
            using(var b=new SolidBrush(color)) using(var f=new StringFormat {Alignment=center?StringAlignment.Center:StringAlignment.Near,LineAlignment=StringAlignment.Center,Trimming=StringTrimming.None,FormatFlags=StringFormatFlags.NoWrap})
                g.DrawString(text,font,b,r,f);
        }
        static void Arrow(Graphics g,float x1,float y1,float x2,float y2,bool both) {
            using(var p=new Pen(Theme.Muted,1.6f)) using(var cap=new AdjustableArrowCap(4.5f,4.5f)) {
                p.CustomEndCap=cap; if(both)p.CustomStartCap=cap;
                g.DrawLine(p,x1,y1,x2,y2);
            }
        }
    }
    sealed class SetupForm : Form {
        const int StepTarget=0, StepModels=1, StepImport=2, StepFinalize=3, StepSitl=4, StepTrouble=5, StepAbout=6;
        readonly string work, payload;
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength=8*1024*1024 };
        readonly float scale=1f;
        ComboBox installs, roots; CheckedListBox models; CheckBox brake, paths;
        TextBox log, tlog; Label state, tip, selectionInfo, headerTarget, badge, importTitle, importHow;
        ProgressBar progress; ListView prepareList, importList, finalizeList; Panel pageHost, logPanel; Button nextFromFinalize; TableLayoutPanel content;
        StatusItem stLink, stPause, stController, stSitl;
        readonly List<StepButton> steps = new List<StepButton>(); readonly List<Control> pages = new List<Control>();
        readonly List<string> detectedRoots = new List<string>(); readonly List<Button> buttons = new List<Button>();
        readonly Timer statusTimer = new Timer { Interval=900 };
        bool busy, statusBusy; string lastManifest=""; int current=-1;
        public SetupForm(string workRoot) {
            work=workRoot; Directory.CreateDirectory(work);
            payload=ExtractPayload();
            Text="SJ-ARC | RealFlight VTOL 설치 도우미 v0.2.2";
            Icon appIcon=null;
            try {appIcon=System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);Icon=appIcon;} catch(Exception) {}
            Font=new Font("맑은 고딕",10F); AutoScaleMode=AutoScaleMode.Dpi;
            using(var g=CreateGraphics()) scale=Math.Max(1f,g.DpiX/96f);
            var area=Screen.FromPoint(Cursor.Position).WorkingArea;
            Size=new Size(Math.Min(P(1136),area.Width-20),Math.Min(P(880),area.Height-20));
            MinimumSize=new Size(Math.Min(P(900),area.Width-20),Math.Min(P(620),area.Height-20)); StartPosition=FormStartPosition.CenterScreen;
            BackColor=Theme.Page;
            var layout=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=3,Padding=new Padding(P(14),P(12),P(14),P(6))};
            layout.RowStyles.Add(new RowStyle(SizeType.Percent,100)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,P(30))); layout.RowStyles.Add(new RowStyle(SizeType.Absolute,P(42)));
            Controls.Add(layout);
            var card=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=3,BackColor=Theme.Card,Margin=new Padding(0)};
            card.RowStyles.Add(new RowStyle(SizeType.Absolute,P(64))); card.RowStyles.Add(new RowStyle(SizeType.Percent,100)); card.RowStyles.Add(new RowStyle(SizeType.Absolute,P(40)));
            card.Paint+=(s,e)=>{using(var pen=new Pen(Theme.Line))e.Graphics.DrawRectangle(pen,0,0,card.Width-1,card.Height-1);};
            layout.Controls.Add(card,0,0);
            card.Controls.Add(BuildHeader(appIcon),0,0);
            var body=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=new Padding(1,0,1,0),BackColor=Theme.Card};
            body.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,P(212))); body.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            card.Controls.Add(body,0,1);
            body.Controls.Add(BuildRail(),0,0);
            content=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=2,Padding=new Padding(P(22),P(18),P(20),P(10)),Margin=new Padding(0),BackColor=Theme.Card};
            content.RowStyles.Add(new RowStyle(SizeType.Percent,100)); content.RowStyles.Add(new RowStyle(SizeType.Absolute,P(150)));
            pageHost=new Panel {Dock=DockStyle.Fill,Margin=new Padding(0)};
            content.Controls.Add(pageHost,0,0);
            content.Controls.Add(BuildLog(),0,1);
            body.Controls.Add(content,1,0);
            card.Controls.Add(BuildStatusStrip(),0,2);
            var statusRow=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,Margin=new Padding(0)}; statusRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); statusRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,P(155)));
            state=new Label {Text="설치된 RealFlight를 확인하고 있습니다…",Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleLeft,ForeColor=Theme.Text};
            progress=new ProgressBar {Dock=DockStyle.Fill,Visible=false,Style=ProgressBarStyle.Marquee,Margin=new Padding(4,P(8),4,P(8))};
            statusRow.Controls.Add(state,0,0); statusRow.Controls.Add(progress,1,0); layout.Controls.Add(statusRow,0,1);
            layout.Controls.Add(new Label {Dock=DockStyle.Fill,Text="기획·교육 적용·검증: 이충현  |  세종사이버대학교 드론로봇융합학과 초빙교수\nAI 개발도구 활용 · 개인 제작 교육지원 도구 · 대학 / RealFlight / MFE / ArduPilot의 공식 제품이 아닙니다.",ForeColor=Theme.Muted,Font=new Font(Font.FontFamily,8.5F),TextAlign=ContentAlignment.MiddleLeft},0,2);
            BuildTargetPage(); BuildModelsPage(); BuildImportPage(); BuildFinalizePage(); BuildSitlPage(); BuildTroublePage(); BuildAboutPage();
            ShowStep(StepTarget);
            statusTimer.Tick+=async(s,e)=>{statusTimer.Stop();await RefreshStatus();};
            Shown+=async(s,e)=>{await Scan();await RefreshStatus();};
            FormClosing+=(s,e)=>{ if(busy) {e.Cancel=true;MessageBox.Show(this,"백업·파일 쓰기가 진행 중입니다. 작업이 끝난 뒤 닫아 주세요.","작업 중");} };
        }
        int P(int px) {return (int)Math.Round(px*scale);}
        // ---------------------------------------------------------------- frame
        Control BuildHeader(Icon appIcon) {
            var h=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=3,RowCount=1,Padding=new Padding(P(16),P(10),P(16),P(8)),Margin=new Padding(1,1,1,0),BackColor=Theme.Card};
            h.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,P(46))); h.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); h.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            h.Paint+=(s,e)=>{using(var pen=new Pen(Theme.Line))e.Graphics.DrawLine(pen,0,h.Height-1,h.Width,h.Height-1);};
            var pic=new PictureBox {Size=new Size(P(36),P(36)),SizeMode=PictureBoxSizeMode.Zoom,Margin=new Padding(0,P(2),0,0)};
            if(appIcon!=null) pic.Image=appIcon.ToBitmap();
            h.Controls.Add(pic,0,0);
            var titles=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,Margin=new Padding(0)};
            titles.Controls.Add(new Label {Text="SJ-ARC VTOL 실습환경 설치 도우미",AutoSize=true,Font=new Font(Font.FontFamily,13F,FontStyle.Bold),ForeColor=Theme.Text,Margin=new Padding(0)});
            headerTarget=new Label {Text="RealFlight 설치를 확인하고 있습니다…",AutoSize=true,ForeColor=Theme.Muted,Font=new Font(Font.FontFamily,9F),Margin=new Padding(1,P(2),0,0)};
            titles.Controls.Add(headerTarget); h.Controls.Add(titles,1,0);
            badge=new Label {Text="상태 확인 중",AutoSize=true,Padding=new Padding(P(10),P(4),P(10),P(4)),Margin=new Padding(0,P(8),0,0),BackColor=Theme.Hover,ForeColor=Theme.Muted,Font=new Font(Font.FontFamily,9F)};
            h.Controls.Add(badge,2,0);
            return h;
        }
        Control BuildRail() {
            var rail=new Panel {Dock=DockStyle.Fill,Padding=new Padding(P(10),P(14),P(10),P(10)),Margin=new Padding(0),BackColor=Theme.Card};
            rail.Paint+=(s,e)=>{using(var pen=new Pen(Theme.Line))e.Graphics.DrawLine(pen,rail.Width-1,0,rail.Width-1,rail.Height);};
            string[] captions={"1. 대상 확인","2. 모델 준비","3. RF에서 Import","4. 검사·패치","5. SITL 연결","연결 문제 해결","도움말·출처"};
            for(int i=0;i<captions.Length;i++) {
                var b=new StepButton(captions[i],i==StepTarget?StepButton.Current:(i>=StepTrouble?StepButton.Utility:StepButton.Pending)) {Height=P(40)};
                int index=i; b.Click+=(s,e)=>ShowStep(index); steps.Add(b);
            }
            // Dock=Top stacks the last added control on top, so add in reverse; a thin rule separates the utilities.
            for(int i=steps.Count-1;i>=0;i--) {
                rail.Controls.Add(steps[i]);
                if(i==StepTrouble) {var rule=new Panel {Dock=DockStyle.Top,Height=P(17)};rule.Paint+=(s,e)=>{using(var pen=new Pen(Theme.Line))e.Graphics.DrawLine(pen,4,rule.Height/2,rule.Width-4,rule.Height/2);};rail.Controls.Add(rule);}
            }
            return rail;
        }
        Control BuildLog() {
            logPanel=new Panel {Dock=DockStyle.Fill,Margin=new Padding(0,P(8),0,0)};
            log=new TextBox {Dock=DockStyle.Fill,Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,WordWrap=false,BackColor=Color.FromArgb(250,251,253),Font=new Font("Consolas",9F),BorderStyle=BorderStyle.FixedSingle};
            logPanel.Controls.Add(log);
            logPanel.Controls.Add(new Label {Text="작업 기록 — 완료 표시는 파일 검사 결과이며, 비행 준비 완료를 뜻하지 않습니다.",Dock=DockStyle.Top,Height=P(22),ForeColor=Theme.Muted,Font=new Font(Font.FontFamily,9F)});
            return logPanel;
        }
        Control BuildStatusStrip() {
            var strip=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false,Padding=new Padding(P(16),P(9),P(8),0),Margin=new Padding(1,0,1,1),BackColor=Theme.Card,Font=new Font(Font.FontFamily,9F)};
            strip.Paint+=(s,e)=>{using(var pen=new Pen(Theme.Line))e.Graphics.DrawLine(pen,0,0,strip.Width,0);};
            stLink=new StatusItem("RealFlight Link 확인 중"); stPause=new StatusItem("일시정지 확인 중"); stController=new StatusItem("조종기 확인 중"); stSitl=new StatusItem("SITL 확인 중");
            foreach(var item in new[]{stLink,stPause,stController,stSitl}) strip.Controls.Add(item);
            var refresh=new LinkLabel {Text="새로고침",AutoSize=true,LinkColor=Theme.Accent,Margin=new Padding(P(4),P(4),0,0)};
            refresh.LinkClicked+=async(s,e)=>await RefreshStatus();
            strip.Controls.Add(refresh);
            return strip;
        }
        // ---------------------------------------------------------------- pages
        TableLayoutPanel NewPage(string title,string description,bool scroll=true) {
            // Scrolling pages: an AutoScroll panel around an auto-sized table. Fixed pages: a filling table whose last rows stretch.
            var page=new TableLayoutPanel {ColumnCount=1,Margin=new Padding(0),Padding=new Padding(0,0,P(6),0)};
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            Control host=page;
            if(scroll) {page.Dock=DockStyle.Top;page.AutoSize=true;page.AutoSizeMode=AutoSizeMode.GrowAndShrink;host=new Panel {Dock=DockStyle.Fill,AutoScroll=true,Margin=new Padding(0)};host.Controls.Add(page);}
            else page.Dock=DockStyle.Fill;
            host.Visible=false;
            Add(page,new Label {Text=title,AutoSize=true,Font=new Font(Font.FontFamily,14F,FontStyle.Bold),ForeColor=Theme.Text,Margin=new Padding(0,0,0,P(4))});
            if(description!=null) Add(page,Note(description,P(12)));
            pages.Add(host); pageHost.Controls.Add(host);
            return page;
        }
        Label Note(string text,int bottom) {return new Label {Text=text,AutoSize=true,MaximumSize=new Size(P(800),0),ForeColor=Theme.Muted,Margin=new Padding(0,0,0,bottom)};}
        Label Caption(string text) {return new Label {Text=text,AutoSize=true,ForeColor=Theme.Text,Font=new Font(Font,FontStyle.Bold),Margin=new Padding(0,P(6),0,P(4))};}
        void Add(TableLayoutPanel page,Control c) {page.RowStyles.Add(new RowStyle(SizeType.AutoSize));page.Controls.Add(c,0,page.RowCount);page.RowCount++;}
        void AddFill(TableLayoutPanel page,Control c,float percent) {page.RowStyles.Add(new RowStyle(SizeType.Percent,percent));c.Dock=DockStyle.Fill;page.Controls.Add(c,0,page.RowCount);page.RowCount++;}

        FlowLayoutPanel Row() {return new FlowLayoutPanel {AutoSize=true,WrapContents=true,Margin=new Padding(0,P(4),0,P(4)),Dock=DockStyle.Fill};}
        Button Button(string text,EventHandler handler,bool primary=false) {
            var b=new Button {Text=text,AutoSize=true,MinimumSize=new Size(P(120),P(36)),Padding=new Padding(P(8),P(2),P(8),P(2)),Margin=new Padding(0,P(4),P(8),P(4)),FlatStyle=FlatStyle.Flat,BackColor=primary?Theme.Accent:Theme.Card,ForeColor=primary?Color.White:Theme.Text,Cursor=Cursors.Hand};
            b.FlatAppearance.BorderColor=primary?Theme.Accent:Color.FromArgb(197,207,216); b.Click+=handler; buttons.Add(b); return b;
        }
        ListView Results(int height,params string[] columns) {
            var v=new ListView {View=View.Details,FullRowSelect=true,HeaderStyle=ColumnHeaderStyle.Nonclickable,Height=P(height),Dock=DockStyle.Fill,BorderStyle=BorderStyle.FixedSingle,Margin=new Padding(0,P(8),0,P(8))};
            foreach(var c in columns) v.Columns.Add(c);
            v.Resize+=(s,e)=>{int w=v.ClientSize.Width;if(w<=0||v.Columns.Count==0)return;int first=(int)(w*0.42);v.Columns[0].Width=first;for(int i=1;i<v.Columns.Count;i++)v.Columns[i].Width=(w-first)/(v.Columns.Count-1);};
            return v;
        }
        void Fill(ListView v,IEnumerable<string[]> rows) {
            v.BeginUpdate(); v.Items.Clear();
            foreach(var r in rows) {
                var item=new ListViewItem(r[0]) {UseItemStyleForSubItems=false};
                for(int i=1;i<r.Length;i++) item.SubItems.Add(r[i]);
                if(r.Length>1) item.SubItems[1].ForeColor=r[1].StartsWith("Import")?Theme.Warn:(r[1].EndsWith("완료")?Theme.Good:Theme.Text);
                v.Items.Add(item);
            }
            v.EndUpdate();
        }
        void BuildTargetPage() {
            var p=NewPage("사용할 RealFlight를 확인하세요","자동으로 찾은 RealFlight와 사용자 문서 폴더입니다. 여러 버전이 설치되어 있으면 이번에 설정할 버전 하나를 고르세요. 선택한 한 곳에만 적용합니다.");
            Add(p,Caption("RealFlight 실행 파일"));
            installs=new ComboBox {Dock=DockStyle.Fill,DropDownStyle=ComboBoxStyle.DropDownList,DropDownWidth=P(1000),Margin=new Padding(0,0,0,P(4))};
            installs.SelectedIndexChanged+=(s,e)=>SuggestRoot(); Add(p,installs);
            var scan=Row(); scan.Controls.Add(Button("다시 검색",async(s,e)=>await Scan())); scan.Controls.Add(Button("실행 파일 직접 선택",async(s,e)=>await PickExe())); Add(p,scan);
            Add(p,Caption("사용자 문서 폴더"));
            var rootRow=new TableLayoutPanel {Dock=DockStyle.Fill,AutoSize=true,ColumnCount=2,Margin=new Padding(0)}; rootRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); rootRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            roots=new ComboBox {Dock=DockStyle.Fill,DropDownStyle=ComboBoxStyle.DropDown,Margin=new Padding(0,P(5),P(8),0)}; roots.TextChanged+=(s,e)=>TargetChanged();
            rootRow.Controls.Add(roots,0,0); rootRow.Controls.Add(Button("폴더 선택",(s,e)=>PickRoot()),1,0); Add(p,rootRow);
            selectionInfo=new Label {Text="사용할 버전을 먼저 선택하세요.",AutoSize=true,MaximumSize=new Size(P(800),0),ForeColor=Theme.Muted,Margin=new Padding(0,P(8),0,P(10))}; Add(p,selectionInfo);
            var next=Row(); next.Controls.Add(Button("다음: 모델 준비",(s,e)=>{if(TargetOnly()){steps[StepTarget].Mark=StepButton.Done;if(steps[StepModels].Mark==StepButton.Pending)steps[StepModels].Mark=StepButton.Current;ShowStep(StepModels);}},true)); Add(p,next);
        }
        void BuildModelsPage() {
            var p=NewPage("설치하거나 보정할 기종을 고르세요","이미 설치된 기종은 CH8~12 신호를 보정하고, 아직 없는 기종은 Import할 원본 RFX를 준비합니다. 바꾸기 전 파일은 모두 백업합니다.");
            var grid=new TableLayoutPanel {Dock=DockStyle.Fill,AutoSize=true,ColumnCount=2,Margin=new Padding(0)}; grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,P(320))); grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            models=new CheckedListBox {CheckOnClick=true,Height=P(112),Dock=DockStyle.Fill,BorderStyle=BorderStyle.FixedSingle,BackColor=Color.White,IntegralHeight=false,Margin=new Padding(0)};
            models.Items.Add(new ModelChoice {Key="S",Title="MFE Striver mini VTOL"},true); models.Items.Add(new ModelChoice {Key="P",Title="MFE Pioneer VTOL"},true); models.Items.Add(new ModelChoice {Key="F",Title="MFE Fighter VTOL"},true); models.Items.Add(new ModelChoice {Key="H",Title="MFE Hero VTOL"},true);
            grid.Controls.Add(models,0,0);
            var options=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,AutoSize=true,WrapContents=false,Padding=new Padding(P(14),0,0,0),Margin=new Padding(0)};
            brake=new CheckBox {Text="전진 프롭 브레이크 보정 포함",Checked=true,AutoSize=true,Margin=new Padding(0,0,0,P(4))}; options.Controls.Add(brake);
            paths=new CheckBox {Text="모델·텍스처 경로 보정 (Evolution 전용 · RF 8/9는 신호만 보정)",Checked=true,Enabled=false,AutoSize=true,Margin=new Padding(0,0,0,P(6))}; options.Controls.Add(paths);
            options.Controls.Add(new Label {Text="PID와 조종기 보정값은 바꾸지 않습니다.\n원본이 이 EXE 폴더에 있으면 인터넷 없이 쓰고, 없으면 GitHub에서 약 13 MB를 받습니다. 모두 해시를 검증합니다.",AutoSize=true,MaximumSize=new Size(P(440),0),ForeColor=Theme.Muted});
            grid.Controls.Add(options,1,0); Add(p,grid);
            var actions=Row(); actions.Controls.Add(Button("모델 준비 / 기존 모델 패치",async(s,e)=>await RunSetup("Prepare"),true)); actions.Controls.Add(Button("Import 폴더 열기",(s,e)=>OpenFolder("RFX\\SJARC"))); Add(p,actions);
            prepareList=Results(130,"기종","상태","Import할 파일"); Add(p,prepareList);
        }
        void BuildImportPage() {
            var p=NewPage("RealFlight에서 Import하세요",null);
            importTitle=(Label)p.Controls[0];
            importHow=Note("먼저 '2. 모델 준비'를 누르면 Import할 파일이 여기에 나옵니다.",P(10)); Add(p,importHow);
            importList=Results(120,"Import할 파일","상태","폴더"); Add(p,importList);
            var row=Row(); row.Controls.Add(Button("RealFlight 열기",(s,e)=>LaunchRF(),true)); row.Controls.Add(Button("Import 폴더 열기",(s,e)=>OpenFolder("RFX\\SJARC")));
            row.Controls.Add(Button("Import 끝냄 → 다음",(s,e)=>{steps[StepImport].Mark=StepButton.Done;steps[StepFinalize].Mark=StepButton.Current;ShowStep(StepFinalize);})); Add(p,row);
        }
        void BuildFinalizePage() {
            var p=NewPage("Import한 기종을 검사하고 패치하세요","RealFlight · Mission Planner · SITL을 모두 종료한 뒤 누르세요. 바꾸기 전 파일은 백업하고, 끝나면 파일 해시로 결과를 검사합니다. 이미 설치된 기종은 다시 Import하지 않습니다.");
            var row=Row(); row.Controls.Add(Button("Import 후 검사·패치",async(s,e)=>await RunSetup("Finalize"),true)); row.Controls.Add(Button("백업에서 복구",async(s,e)=>await Restore())); row.Controls.Add(Button("작업 보고서 폴더",(s,e)=>OpenLocal(Path.Combine(work,"reports")))); Add(p,row);
            finalizeList=Results(130,"기종","상태","비고"); Add(p,finalizeList);
            tip=new Label {Text="Import 끝에 '경로를 찾을 수 없습니다' 창이 나왔다면 확인을 누른 뒤 RF를 완전히 종료하고 위 버튼을 누르세요.",AutoSize=true,MaximumSize=new Size(P(800),0),BackColor=Theme.AccentSoft,ForeColor=Theme.AccentText,Padding=new Padding(P(10)),Margin=new Padding(0,P(4),0,P(6))};
            Add(p,tip);
            var next=Row(); nextFromFinalize=Button("다음: SITL 연결",(s,e)=>ShowStep(StepSitl),true); nextFromFinalize.Visible=false; next.Controls.Add(nextFromFinalize); Add(p,next);
        }
        void BuildSitlPage() {
            var p=NewPage("Mission Planner에서 SITL을 연결하세요",null,false);
            Add(p,new ConnectionDiagram {Height=P(158),Dock=DockStyle.Fill,Margin=new Padding(0,P(2),0,P(4))});
            var start=Row(); start.Controls.Add(Button("SITL 시작 (flightaxis)",async(s,e)=>await StartSitl(),true)); start.Controls.Add(Button("SITL 종료",async(s,e)=>await StopSitl())); Add(p,start);
            var callout=new Label {Text="[SITL 시작]은 항상 flightaxis로, 같은 파라미터 저장소로, Wipe 없이 켜고 Mission Planner가 스스로 연결합니다(UDP 14550). RealFlight를 먼저 켜고 기체를 고른 뒤 누르세요.\nMP의 Simulation 탭에서 직접 켤 때는 Model = flightaxis를 꼭 고르세요. 안 고르면 RF 기체는 넘어지는데 MP 화면은 그대로입니다(배터리 12.60V 고정).",AutoSize=true,MaximumSize=new Size(P(800),0),BackColor=Theme.WarnSoft,ForeColor=Color.FromArgb(99,56,6),Padding=new Padding(P(12)),Margin=new Padding(0,P(4),0,P(6))};
            Add(p,callout);
            var row=Row(); row.Controls.Add(Button("파라미터 폴더 열기",(s,e)=>OpenFolder(".SJARC\\Parameters"))); row.Controls.Add(Button("로컬 연결 포트 확인",async(s,e)=>await Probe()));
            row.Controls.Add(Button("공식 연결 문서",(s,e)=>Process.Start(new ProcessStartInfo("https://ardupilot.org/dev/docs/sitl-with-realflight.html") {UseShellExecute=true}))); Add(p,row);
            var text=new RichTextBox {ReadOnly=true,BorderStyle=BorderStyle.None,BackColor=Color.White,Font=new Font("맑은 고딕",10.5F),DetectUrls=true,Text=File.ReadAllText(Path.Combine(payload,"GUIDE_KO.txt"),Encoding.UTF8),Margin=new Padding(0,P(6),0,0)};
            text.LinkClicked+=(s,e)=>Process.Start(new ProcessStartInfo(e.LinkText) {UseShellExecute=true}); AddFill(p,text,100);
        }
        void BuildTroublePage() {
            var p=NewPage("연결 문제 해결","SITL 연결 중 RealFlight가 '응답 없음'이 되거나, 처음 설정 뒤로 연결이 안 될 때 씁니다. 진단은 읽기만 합니다. 초기화는 파일을 지우지 않고 백업 이름으로 옮기며, 되돌리기가 있습니다.",false);
            var r1=Row(); r1.Controls.Add(Button("① 진단 보고서 만들기 (읽기 전용)",async(s,e)=>await Diagnose(),true)); r1.Controls.Add(Button("② 남은 SITL 창 종료",async(s,e)=>await StopSitl())); r1.Controls.Add(Button("보고서 폴더 열기",(s,e)=>OpenLocal(Path.Combine(work,"reports")))); Add(p,r1);
            var r2=Row(); r2.Controls.Add(Button("③ SITL 저장 설정 초기화",async(s,e)=>await Maintenance("ResetSitl"))); r2.Controls.Add(Button("SITL 설정 되돌리기",async(s,e)=>await Maintenance("RestoreSitl"))); Add(p,r2);
            var r3=Row(); r3.Controls.Add(Button("④ RealFlight 설정 초기화 (최후 수단)",async(s,e)=>await Maintenance("ResetRfIni"))); r3.Controls.Add(Button("RF 설정 되돌리기",async(s,e)=>await Maintenance("RestoreRfIni"))); Add(p,r3);
            AddFill(p,new RichTextBox {ReadOnly=true,BorderStyle=BorderStyle.None,BackColor=Color.White,Font=new Font("맑은 고딕",10F),Text=File.ReadAllText(Path.Combine(payload,"TROUBLESHOOT_KO.txt"),Encoding.UTF8),Margin=new Padding(0,P(6),0,0)},55);
            tlog=new TextBox {Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,WordWrap=false,BackColor=Color.FromArgb(250,251,253),Font=new Font("Consolas",9F),BorderStyle=BorderStyle.FixedSingle,Margin=new Padding(0,P(8),0,0)};
            AddFill(p,tlog,45);
        }
        void BuildAboutPage() {
            var p=NewPage("범위 · 안전 · 출처",null,false);
            AddFill(p,new TextBox {Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,BackColor=Color.White,BorderStyle=BorderStyle.None,Font=new Font("맑은 고딕",10.5F),Text=File.ReadAllText(Path.Combine(payload,"README_KO.md"),Encoding.UTF8).Replace("\r\n","\n").Replace("\n","\r\n")},100);
        }
        void ShowStep(int index) {
            if(index<0||index>=pages.Count) return;
            current=index;
            for(int i=0;i<pages.Count;i++) {pages[i].Visible=i==index;steps[i].Selected=i==index;}
            logPanel.Visible=index<=StepFinalize;
            content.RowStyles[1].Height=index<=StepFinalize?P(150):0;
            if(index==StepSitl||index==StepTrouble) {var ignored=RefreshStatus();}
        }
        // ---------------------------------------------------------------- status strip
        static bool? Flag(Dictionary<string,object> d,string key) {if(!d.ContainsKey(key)||d[key]==null)return null;return Convert.ToBoolean(d[key]);}
        async Task RefreshStatus() {
            if(statusBusy||busy) return;
            statusBusy=true;
            try {
                var install=installs.SelectedItem as Install;
                var r=await Execute(new Dictionary<string,object>{{"Action","Status"},{"Executable",install==null?"":install.Path},{"Root",RootText()}},false);
                bool running=Flag(r,"RfRunning")==true||Flag(r,"MpRunning")==true||Flag(r,"SitlRunning")==true;
                badge.Text=running?"RF·MP 실행 중 · 파일 작업은 종료 후":"RF·MP 꺼짐 · 파일 작업 가능";
                badge.BackColor=running?Theme.WarnSoft:Theme.GoodSoft; badge.ForeColor=running?Theme.Warn:Theme.Good;
                var link=Flag(r,"LinkEnabled");
                stLink.Set(link==true?Theme.Good:(link==false?Theme.Bad:Theme.Faint),link==true?"RealFlight Link 켜짐":(link==false?"RealFlight Link 꺼짐":"RealFlight Link 확인 불가"));
                var pause=Flag(r,"PauseOn");
                stPause.Set(pause==false?Theme.Good:(pause==true?Theme.Bad:Theme.Faint),pause==false?"일시정지 꺼짐":(pause==true?"일시정지 켜짐 (꺼야 함)":"일시정지 확인 불가"));
                var controller=Flag(r,"ControllerSelected");
                stController.Set(controller==true?Theme.Good:(controller==false?Theme.Warn:Theme.Faint),controller==true?"조종기 선택됨":(controller==false?"조종기 선택 기록 없음":"조종기 확인 불가"));
                var sitl=Flag(r,"SitlRunning"); var flightAxis=Flag(r,"SitlFlightAxis");
                if(sitl!=true) stSitl.Set(Theme.Faint,"SITL 꺼짐 · 켜면 flightaxis 확인");
                else if(flightAxis==true) stSitl.Set(Theme.Good,"SITL flightaxis로 실행 중");
                else if(flightAxis==false) stSitl.Set(Theme.Bad,"SITL이 flightaxis 아님 → Model 다시 선택");
                else stSitl.Set(Theme.Faint,"SITL 실행 중 · 모델 확인 불가");
            } catch(Exception) {
                badge.Text="상태 확인 실패"; badge.BackColor=Theme.Hover; badge.ForeColor=Theme.Muted;
            } finally {statusBusy=false;}
        }
        // ---------------------------------------------------------------- shared
        void SetBusy(bool value,string message) {busy=value;foreach(var b in buttons)b.Enabled=!value;installs.Enabled=roots.Enabled=models.Enabled=brake.Enabled=paths.Enabled=!value;UpdatePathOption();progress.Visible=value;state.Text=message;}
        // Path repair only exists for Evolution; RF 8/9 crashed on FLY with it, so the backend never repairs there.
        bool IsEvolution() {var install=installs.SelectedItem as Install;return install!=null&&install.Edition=="Evolution";}
        void UpdatePathOption() {if(paths!=null)paths.Enabled=!busy&&IsEvolution();}
        void Append(string s) {log.AppendText(DateTime.Now.ToString("HH:mm:ss")+"  "+s+Environment.NewLine);}
        static string Str(Dictionary<string,object> d,string key) {return d.ContainsKey(key)&&d[key]!=null?Convert.ToString(d[key]):"";}
        static IEnumerable<Dictionary<string,object>> Objects(Dictionary<string,object> d,string key) {
            if(!d.ContainsKey(key)||!(d[key] is IEnumerable))yield break;
            foreach(var x in (IEnumerable)d[key]) if(x is Dictionary<string,object>)yield return (Dictionary<string,object>)x;
        }
        static IEnumerable<string> Strings(Dictionary<string,object> d,string key) {
            if(!d.ContainsKey(key)||d[key]==null||d[key] is string)yield break;
            var items=d[key] as IEnumerable;if(items==null)yield break;
            foreach(var x in items)yield return Convert.ToString(x);
        }
        Dictionary<string,object> Basic(string action) {
            var install=installs.SelectedItem as Install;
            var selected=new List<string>();foreach(ModelChoice m in models.CheckedItems)selected.Add(m.Key);
            return new Dictionary<string,object> {{"Action",action},{"Executable",install==null?"":install.Path},{"Root",RootText()},{"Models",selected.ToArray()},{"Cache",Path.Combine(work,"cache")},{"SourceFolder",AppDomain.CurrentDomain.BaseDirectory},{"Brake",brake.Checked},{"RepairPaths",paths.Checked&&IsEvolution()}};
        }
        string RootText() {return roots.Text.Trim().Trim('"').Trim();}
        void AppendList(Dictionary<string,object> d,string key,string prefix) {foreach(string s in Strings(d,key))Append(prefix+s);}
        async Task<Dictionary<string,object>> Execute(Dictionary<string,object> request,bool keep=true) {
            // Recheck the immutable embedded scripts before executing them.
            VerifyPayload();
            Directory.CreateDirectory(Path.Combine(work,"requests"));Directory.CreateDirectory(Path.Combine(work,"reports"));
            string id=DateTime.Now.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N").Substring(0,8);
            string req=Path.Combine(work,"requests",id+".json");File.WriteAllText(req,json.Serialize(request),new UTF8Encoding(false));
            string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe");
            var start=new ProcessStartInfo(ps,"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+Path.Combine(payload,"Backend.ps1")+"\" -RequestFile \""+req+"\"") {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
            string output;
            try {output=await Task.Run(()=>{using(var process=Process.Start(start)) {var stdout=process.StandardOutput.ReadToEndAsync();var stderr=process.StandardError.ReadToEndAsync();process.WaitForExit();Task.WaitAll(stdout,stderr);if(String.IsNullOrWhiteSpace(stdout.Result))throw new Exception(stderr.Result);return stdout.Result;}});}
            finally {if(!keep)try{File.Delete(req);}catch(IOException){}}
            // Status polls are not kept: the report folder is for real work runs.
            if(keep) File.WriteAllText(Path.Combine(work,"reports",id+".json"),output,new UTF8Encoding(false));
            var result=json.DeserializeObject(output) as Dictionary<string,object>;
            if(result==null)throw new Exception("검사 결과를 읽지 못했습니다. 보고서 폴더를 확인하세요.");
            if(!result.ContainsKey("Success")||!Convert.ToBoolean(result["Success"]))throw new Exception(Str(result,"Error"));
            return result;
        }
        // ---------------------------------------------------------------- target
        async Task Scan() {
            if(busy)return;SetBusy(true,"설치 확인 중… (읽기 전용)");
            try {
                var data=await Execute(new Dictionary<string,object>{{"Action","Detect"}});
                detectedRoots.Clear();installs.Items.Clear();roots.Items.Clear();roots.Text="";
                foreach(var x in Objects(data,"Installations"))installs.Items.Add(new Install {Path=Str(x,"Path"),Label=Str(x,"Label"),Edition=Str(x,"Edition")});
                if(data.ContainsKey("Roots"))foreach(var r in (IEnumerable)data["Roots"])detectedRoots.Add(Convert.ToString(r));
                installs.SelectedIndex=TargetSelection.InitialInstall(installs.Items.Count);
                TargetChanged();
                Append("RealFlight 실행 파일 "+installs.Items.Count+"개, 사용자 폴더 "+detectedRoots.Count+"개 발견. Trainer / RealFlight-X 제외.");
                if(installs.Items.Count==0)Append("자동 검색 실패: RealFlight.exe 또는 RealFlight64.exe를 직접 선택하세요. 프로그램 설치·구매는 자동으로 하지 않습니다.");
                if(installs.Items.Count>1)Append("여러 버전 발견: 대상 프로그램과 사용자 문서 폴더를 직접 선택하세요.");
                SetBusy(false,"설치 확인 완료 · 대상과 모델을 확인한 뒤 진행하세요.");
            }catch(Exception ex){Fail(ex);}
        }
        void SuggestRoot() {
            roots.Items.Clear();roots.SelectedIndex=-1;roots.Text="";
            var install=installs.SelectedItem as Install;
            if(install!=null) {
                foreach(string root in TargetSelection.Candidates(install.Edition,detectedRoots))roots.Items.Add(root);
                roots.SelectedIndex=TargetSelection.InitialRoot(roots.Items.Count,detectedRoots.Count);
            }
            TargetChanged();
        }
        void TargetChanged() {
            lastManifest="";
            if(selectionInfo==null)return;
            var install=installs.SelectedItem as Install;
            bool ready=false;
            if(install==null) selectionInfo.Text="위 목록에서 사용할 제품을 직접 선택하세요. 아직 대상이 선택되지 않았습니다.";
            else if(String.IsNullOrWhiteSpace(roots.Text)) selectionInfo.Text="선택: "+install.Label+"\n해당 버전의 사용자 문서 폴더를 선택하세요. 후보 "+roots.Items.Count+"개 · 목록에 없으면 해당 RF를 한 번 실행·종료한 후 다시 검색하거나 폴더를 지정하세요.";
            else if(TargetSelection.KnownMismatch(install.Edition,roots.Text)) selectionInfo.Text="주의: 선택한 실행 파일과 문서 폴더의 버전이 다릅니다. 적용하지 않고 중단합니다.";
            else {selectionInfo.Text="선택: "+install.Label+"\n이 문서 폴더의 기체·설정만 적용합니다. 다른 버전의 문서 폴더는 변경하지 않습니다.";ready=true;}
            headerTarget.Text=install==null?"대상 RealFlight를 선택하세요":install.Label+(String.IsNullOrWhiteSpace(RootText())?"":"  ·  "+Path.GetFileName(RootText().TrimEnd('\\','/')));
            // A new target starts the flow over: later steps belonged to the previous folder.
            steps[StepTarget].Mark=ready?StepButton.Done:StepButton.Current;
            steps[StepModels].Mark=ready?StepButton.Current:StepButton.Pending;
            foreach(int i in new[]{StepImport,StepFinalize,StepSitl})steps[i].Mark=StepButton.Pending;
            if(nextFromFinalize!=null)nextFromFinalize.Visible=false;
            UpdatePathOption();
            statusTimer.Stop();statusTimer.Start();
        }
        string TargetDescription() {
            var install=installs.SelectedItem as Install;
            return (install==null?"선택 안 됨":install.Label+"\n실행 파일: "+install.Path)+"\n문서 폴더: "+RootText();
        }
        async Task PickExe() {
            using(var d=new OpenFileDialog {Title="RealFlight 실행 파일 선택",Filter="RealFlight 실행 파일|RealFlight.exe;RealFlight64.exe",CheckFileExists=true}) {
                if(d.ShowDialog(this)!=DialogResult.OK)return;
                SetBusy(true,"선택한 실행 파일의 제품·버전 확인 중… (읽기 전용)");
                try {
                    var result=await Execute(new Dictionary<string,object>{{"Action","InspectExecutable"},{"Executable",d.FileName}});
                    var data=(Dictionary<string,object>)result["Installation"];
                    var item=new Install {Path=Str(data,"Path"),Label=Str(data,"Label"),Edition=Str(data,"Edition")};
                    Install existing=null;foreach(Install candidate in installs.Items)if(String.Equals(candidate.Path,item.Path,StringComparison.OrdinalIgnoreCase))existing=candidate;
                    if(existing==null)installs.Items.Add(item);installs.SelectedItem=existing??item;
                    Append("실행 파일 확인: "+item);SetBusy(false,"버전 확인 완료 · 해당 문서 폴더를 확인하세요.");
                }catch(Exception ex){Fail(ex);}
            }
        }
        void PickRoot() {using(var d=new FolderBrowserDialog {Description="RealFlight.ini 또는 RealFlight64.ini가 있는 사용자 문서 폴더를 선택하세요.",ShowNewFolderButton=false})if(d.ShowDialog(this)==DialogResult.OK)roots.Text=d.SelectedPath;}
        bool TargetOnly() {
            if(installs.SelectedItem==null||String.IsNullOrWhiteSpace(RootText())){MessageBox.Show(this,"'1. 대상 확인'에서 RealFlight 실행 파일과 사용자 문서 폴더를 먼저 선택하세요.","대상 확인");ShowStep(StepTarget);return false;}
            if(TargetSelection.KnownMismatch(((Install)installs.SelectedItem).Edition,roots.Text)){MessageBox.Show(this,"실행 파일과 문서 폴더의 버전이 다릅니다. 같은 버전으로 선택하세요.","대상 불일치");ShowStep(StepTarget);return false;}
            return true;
        }
        bool TargetReady() {
            if(!TargetOnly())return false;
            if(models.CheckedItems.Count==0){MessageBox.Show(this,"'2. 모델 준비'에서 기종을 하나 이상 고르세요.","기종 확인");ShowStep(StepModels);return false;}
            return true;
        }
        // ---------------------------------------------------------------- setup
        static string StateText(string state) {return state=="SIGNALS_PATCHED"?"보정 완료":(state=="IMPORT_REQUIRED"?"Import 필요":state);}
        async Task RunSetup(string action) {
            if(!TargetReady())return;
            string note=action=="Prepare"?"선택한 모델의 고정 원본을 이 EXE 폴더 또는 GitHub에서 가져와 해시를 검증합니다. 아직 Import 안 된 모델은 원본 RFX를 Import 폴더에 준비하고, 이미 Import된 모델은 신호·경로를 보정합니다.":"선택 모델이 모두 Import되어 있어야 합니다. 기존 파일을 백업한 뒤 신호·경로를 검사하고 필요한 부분을 보정합니다.";
            if(!IsEvolution())note+="\n\nRF 8/9: 모델·텍스처 경로는 RealFlight가 Import한 그대로 두고 CH8~12 신호만 보정합니다. 이전 도우미(v0.1.2/v0.1.3)가 공용 폴더로 바꾼 경로는 RealFlight Import 경로로 되돌립니다(RF 9 FLY 크래시 원인).";else if(!paths.Checked)note+="\n\n경로 보정 끔: 모델·텍스처 경로와 BasedOn은 그대로 두고 CH8~12 신호만 보정합니다.";
            note+="\n\nRealFlight·Mission Planner·ArduPlane SITL을 모두 종료해 주세요.\nRealFlight Link 활성화 및 백그라운드/메뉴 일시정지 해제도 적용합니다.\n조종기 설정과 PID는 변경하지 않습니다. 자동 ARM/이륙은 하지 않습니다.\n\n"+TargetDescription()+"\n\n위 대상 한 곳에만 적용합니다. 계속할까요?";
            if(MessageBox.Show(this,note,"작업 범위 확인",MessageBoxButtons.OKCancel,MessageBoxIcon.Information)!=DialogResult.OK)return;
            SetBusy(true,"모델 준비·검사 중… 다운로드와 텍스처 생성에 시간이 걸릴 수 있습니다.");
            try {
                var result=await Execute(Basic(action));
                if(result.ContainsKey("Transaction")){var t=(Dictionary<string,object>)result["Transaction"];lastManifest=Str(t,"Manifest");if(lastManifest!="")Append("백업: "+lastManifest);}
                var rows=new List<string[]>();var pending=new List<string>();
                foreach(var m in Objects(result,"Models")){string status=Str(m,"State");Append(Str(m,"Model")+" : "+status);rows.Add(new[]{Str(m,"Model"),StateText(status),status=="IMPORT_REQUIRED"?Path.GetFileName(Str(m,"Rfx")):""});if(status=="IMPORT_REQUIRED")pending.Add(Str(m,"Rfx"));}
                AppendList(result,"Notes","");AppendList(result,"Warnings","확인 필요: ");
                var warnings=new List<string>(Strings(result,"Warnings"));
                Append("파라미터 폴더: "+Str(result,"ParamFolder"));
                if(action=="Prepare")Fill(prepareList,rows);else Fill(finalizeList,rows);
                steps[StepModels].Mark=StepButton.Done;
                if(pending.Count>0) {
                    ShowImport(pending);
                    steps[StepImport].Mark=StepButton.Attention;steps[StepFinalize].Mark=StepButton.Pending;
                    SetBusy(false,"모델 파일 준비 완료 · RealFlight에서 Import가 필요합니다.");
                    ShowStep(StepImport);
                } else {
                    if(action=="Prepare")Fill(finalizeList,rows);
                    foreach(int i in new[]{StepImport,StepFinalize})steps[i].Mark=StepButton.Done;
                    steps[StepSitl].Mark=StepButton.Current;
                    tip.Text="선택 기종의 신호 파일 보정을 마쳤습니다. RF 기체 선택에서 원래 이름(STRIVERminiVTOL · Pioneer · fighterVTOL · HERO2180)을 골라 정상 로드를 확인하세요. 다른 이름으로 저장한 사본은 패치되지 않습니다. 비행 검증 완료가 아닙니다."+(warnings.Count>0?"\n\n확인 필요: "+String.Join(" / ",warnings):"");
                    nextFromFinalize.Visible=true;
                    SetBusy(false,"파일 적용·해시 검사 완료 · SITL 파라미터 적용과 DISARM 검증은 별도입니다.");
                    ShowStep(StepFinalize);
                }
            }catch(Exception ex){Fail(ex);}
            await RefreshStatus();
        }
        void ShowImport(List<string> pending) {
            importTitle.Text="RealFlight에서 "+pending.Count+"개 기종을 Import하세요";
            importHow.Text=IsEvolution()
                ?"① My RealFlight → Import → RealFlight Archives를 누르고 아래 파일을 고릅니다.\n② 끝에 '경로를 찾을 수 없습니다' 창이 나오면 확인을 누릅니다.\n③ 모두 가져왔으면 RealFlight를 완전히 종료하고 'Import 끝냄 → 다음'을 누릅니다."
                :"① MFE가 아닌 기본 기체(예: Piper Cub)를 먼저 선택합니다. MFE 기체가 선택된 채로 Import하면 'This battery is in use' 오류가 납니다.\n② Simulation → Import → RealFlight Archive (RFX, G3X)를 누르고 아래 파일을 고릅니다.\n③ 끝에 '경로를 찾을 수 없습니다' 창이 나오면 확인을 누릅니다.\n④ 모두 가져왔으면 RealFlight를 완전히 종료하고 'Import 끝냄 → 다음'을 누릅니다.";
            var rows=new List<string[]>();foreach(string file in pending)rows.Add(new[]{Path.GetFileName(file),"Import 필요",Path.GetDirectoryName(file)});
            Fill(importList,rows);
            foreach(string file in pending)Append("Import할 파일: "+file);
        }
        async Task Restore() {
            if(!TargetReady())return;
            using(var d=new OpenFileDialog {Title="복구할 작업의 manifest.json 선택 (최근 작업부터)",Filter="설치 백업|manifest.json",CheckFileExists=true}) {
                try {d.InitialDirectory=Path.Combine(RootText(),".SJARC","Backups");} catch(ArgumentException) {}
                if(!String.IsNullOrEmpty(lastManifest))d.FileName=lastManifest;
                if(d.ShowDialog(this)!=DialogResult.OK)return;
                if(MessageBox.Show(this,"RF·MP·SITL을 종료하세요. 선택한 작업이 변경한 파일만 복구합니다.\n모델 Import 자체와 ArduPilot 파라미터는 되돌리지 않습니다.\n설치 후 파일이 바뀌었으면 덮어쓰지 않고 중단합니다.\n(RealFlight가 다시 쓴 INI는 이 도구가 바꾼 FlightAxis 키만 되돌립니다.)\n\n진행할까요?","백업 복구",MessageBoxButtons.OKCancel,MessageBoxIcon.Warning)!=DialogResult.OK)return;
                SetBusy(true,"백업과 현재 파일을 대조하고 복구 중…");
                try {var req=Basic("Restore");req["Manifest"]=d.FileName;var r=await Execute(req);Append(Str(r,"Message"));AppendList(r,"Notes","");Append("복구 전 사본: "+Str(r,"Recovery"));SetBusy(false,"선택 작업 복구 완료 · 원본/복구 전 사본 모두 보관했습니다.");}catch(Exception ex){Fail(ex);}
                foreach(int i in new[]{StepFinalize,StepSitl})steps[i].Mark=StepButton.Pending;
                nextFromFinalize.Visible=false;
                await RefreshStatus();
            }
        }
        // ---------------------------------------------------------------- SITL and troubleshooting
        async Task Probe() {
            SetBusy(true,"로컬 TCP 수신 대기 목록 확인 중…");
            try {var r=await Execute(new Dictionary<string,object>{{"Action","Probe"}});var b=new StringBuilder();foreach(var p in Objects(r,"Ports"))b.AppendLine(Str(p,"Port")+" : "+(Convert.ToBoolean(p["Open"])?"수신 대기 있음":"수신 대기 없음"));b.AppendLine("18083: RF FlightAxis / 5760: 기본 SITL TCP\n수신 대기 목록만 검사하며 접속이나 패킷 전송은 하지 않습니다.\n해당 프로세스의 정체·MAVLink·기체·실제 연결 가능 여부는 별도 확인하세요.");SetBusy(false,"포트 목록 검사 완료 · 접속/명령 전송 없음.");MessageBox.Show(this,b.ToString(),"로컬 포트 확인");}catch(Exception ex){Fail(ex);}
        }
        async Task StartSitl() {
            SetBusy(true,"SITL 시작 중… (flightaxis · 같은 저장소 · Wipe 없음)");
            try {
                var r=await Execute(new Dictionary<string,object>{{"Action","StartSitl"}});
                foreach(string s in Strings(r,"Notes"))Append(s);
                var warnings=new List<string>();foreach(string s in Strings(r,"Warnings")){Append("확인 필요: "+s);warnings.Add("• "+Plain(s));}
                bool? auto=Flag(r,"AutoConnect");
                SetBusy(false,"SITL 실행 중 · Mission Planner 연결을 확인하세요.");
                string text="SITL을 flightaxis로 켰습니다. 작업 표시줄에 SITL 검은 창이 최소화되어 있습니다.\n\n"
                    +(auto==false?"Mission Planner의 자동 연결이 꺼져 있습니다. MP 오른쪽 위 연결 단추에서 TCP → 127.0.0.1 → 5760으로 연결하세요.":"Mission Planner가 몇 초 안에 스스로 연결합니다. 오른쪽 위 단추가 DISCONNECT로 바뀌면 연결된 것이니 다시 누르지 마세요.")
                    +"\n\nRealFlight에서 스페이스바(리셋)를 누르면 'FlightAxis Controller Device has been activated'가 나옵니다.";
                if(warnings.Count>0)text+="\n\n확인 필요\n"+String.Join("\n",warnings);
                MessageBox.Show(this,text,"SITL 시작",MessageBoxButtons.OK,MessageBoxIcon.Information);
            }catch(Exception ex){Fail(ex);}
            await Task.Delay(1500);
            await RefreshStatus();
        }
        void TLog(string s) {tlog.AppendText(DateTime.Now.ToString("HH:mm:ss")+"  "+s+Environment.NewLine);Append(s);}
        async Task Diagnose() {
            SetBusy(true,"연결 상태 진단 중… (읽기 전용 · 10초 정도)");
            try {
                var install=installs.SelectedItem as Install;
                var r=await Execute(new Dictionary<string,object>{{"Action","Diagnose"},{"Executable",install==null?"":install.Path},{"Root",RootText()},{"ReportFolder",Path.Combine(work,"reports")}});
                foreach(string s in Strings(r,"Summary"))TLog(s);
                TLog("진단 보고서: "+Str(r,"ReportFile"));TLog("보낼 파일(zip): "+Str(r,"Bundle"));
                SetBusy(false,"진단 완료 · 파일과 설정은 바꾸지 않았습니다.");
                string file=Str(r,"ReportFile");
                if(File.Exists(file))Process.Start(new ProcessStartInfo("notepad.exe","\""+file+"\"") {UseShellExecute=true});
            }catch(Exception ex){Fail(ex);}
            await RefreshStatus();
        }
        async Task StopSitl() {
            if(MessageBox.Show(this,"Mission Planner가 띄운 SITL(검은 창 · ArduPlane 등)만 종료합니다.\n다른 위치에서 실행한 프로그램, Mission Planner, RealFlight는 건드리지 않습니다.\n\n계속할까요?","남은 SITL 창 종료",MessageBoxButtons.OKCancel,MessageBoxIcon.Question)!=DialogResult.OK)return;
            SetBusy(true,"남은 SITL 창 종료 중…");
            try {
                var r=await Execute(new Dictionary<string,object>{{"Action","StopSitl"}});
                int n=0;foreach(string s in Strings(r,"Stopped")){TLog("종료: "+s);n++;}
                foreach(string s in Strings(r,"Skipped"))TLog("건드리지 않음(Mission Planner sitl 폴더 밖): "+s);
                if(n==0)TLog("종료할 SITL 창이 없습니다.");
                SetBusy(false,"SITL 창 정리 완료 · Mission Planner와 RealFlight는 직접 닫으세요.");
            }catch(Exception ex){Fail(ex);}
            await RefreshStatus();
        }
        async Task Maintenance(string action) {
            bool rf=action.EndsWith("RfIni");
            if(rf&&!TargetOnly())return;
            string sitl=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"Mission Planner","sitl","flightaxis");
            string note;
            if(action=="ResetSitl")note="Mission Planner SITL(flightaxis) 저장 폴더의 이름을 백업 이름으로 바꿉니다. 지우지 않습니다.\n\n대상 폴더: "+sitl+"\n(SITL 파라미터 eeprom.bin과 SITL 로그)\n\n다음 SITL은 기본 파라미터로 새로 시작합니다.\n파라미터를 넣기 전에 RF 연결이 되는지 먼저 확인하고, 그다음 기종 param 파일을 다시 불러오세요.\n'SITL 설정 되돌리기'를 누르면 원래대로 돌아갑니다.";
            else if(action=="RestoreSitl")note="도우미가 가장 최근에 백업한 SITL 저장 폴더를 원래 이름(flightaxis)으로 되돌립니다.\n초기화 뒤에 새로 생긴 폴더는 지우지 않고 다른 이름으로 보관합니다.";
            else if(action=="ResetRfIni")note="선택한 RealFlight의 설정 파일(INI)을 백업 폴더로 옮깁니다. 최후 수단입니다.\n\n"+TargetDescription()+"\n\n• 다음에 RF를 실행하면 설정이 처음 상태로 새로 만들어집니다.\n• 다시 해야 할 것: 조종기 선택·보정, Settings → Physics(RealFlight Link = Yes, 배경·메뉴 일시정지 = No, Automatic Reset Delay = 2.0)\n• 기체·모델·조종기 프로필 파일은 바뀌지 않습니다.\n• 'RF 설정 되돌리기'를 누르면 원래 설정 파일이 돌아옵니다.";
            else note="도우미가 가장 최근에 옮겨 둔 RealFlight 설정 파일(INI)을 되돌립니다.\n\n"+TargetDescription()+"\n\n초기화 뒤 RF가 새로 만든 INI는 지우지 않고, 사본을 백업 폴더에 남깁니다.";
            bool reset=action.StartsWith("Reset");
            if(MessageBox.Show(this,note+"\n\nRealFlight · Mission Planner · SITL을 모두 종료한 뒤 확인을 누르세요.",reset?"초기화 (지우지 않고 옮김)":"되돌리기",MessageBoxButtons.OKCancel,reset?MessageBoxIcon.Warning:MessageBoxIcon.Question)!=DialogResult.OK)return;
            SetBusy(true,"처리 중… (파일을 지우지 않고 옮깁니다)");
            try {
                var req=new Dictionary<string,object>{{"Action",action}};
                if(rf){req["Executable"]=((Install)installs.SelectedItem).Path;req["Root"]=RootText();}
                var r=await Execute(req);
                string result=Str(r,"State");
                if(result=="NOTHING_TO_RESET")TLog("초기화할 SITL 저장 폴더가 없습니다. 다음 SITL은 이미 기본 파라미터로 시작합니다.");
                if(Str(r,"Backup")!="")TLog("백업 위치: "+Str(r,"Backup"));
                if(Str(r,"Restored")!="")TLog("되돌림: "+Str(r,"Restored"));
                if(Str(r,"Kept")!="")TLog("보관(지우지 않음): "+Str(r,"Kept"));
                if(result=="SITL_RESET")TLog("다음: RF 실행·기체 선택 → MP Simulation 연결 → 파라미터 넣기 전 연결 확인 → 기종 param Load·Write → SITL 재시작 → 다시 확인");
                if(result=="RF_INI_RESET")TLog("다음: RF 실행 → 조종기 선택·보정 → Settings → Physics(RealFlight Link = Yes, 일시정지 2개 = No, Reset Delay 2.0) → RF 재시작 → 연결 확인");
                SetBusy(false,"완료 · 옮긴 파일은 백업 위치에 그대로 있습니다.");
            }catch(Exception ex){Fail(ex);}
            await RefreshStatus();
        }
        void LaunchRF() {
            var item=installs.SelectedItem as Install;if(item==null){MessageBox.Show(this,"대상 실행 파일을 먼저 선택하세요.");ShowStep(StepTarget);return;}
            if(MessageBox.Show(this,"선택한 RealFlight만 실행합니다. 필요한 새 모델만 Import하세요. 이미 설치된 기체에 덮어쓰기 질문이 나오면 취소하고 확인하세요.\n\n"+TargetDescription()+"\n\n자동 ARM이나 비행 명령은 보내지 않습니다.","RealFlight 열기",MessageBoxButtons.OKCancel)!=DialogResult.OK)return;
            try {var v=FileVersionInfo.GetVersionInfo(item.Path);if(v.ProductName==null||!v.ProductName.Contains("RealFlight")||!new List<string>{"RealFlight.exe","RealFlight64.exe"}.Contains(Path.GetFileName(item.Path)))throw new Exception("검증된 RealFlight 실행 파일을 선택하세요.");Process.Start(new ProcessStartInfo(item.Path){UseShellExecute=true,WorkingDirectory=Path.GetDirectoryName(item.Path)});}catch(Exception ex){MessageBox.Show(this,ex.Message,"실행 오류");}
        }
        void OpenFolder(string relative) {if(String.IsNullOrWhiteSpace(RootText())){MessageBox.Show(this,"사용자 문서 폴더를 먼저 선택하세요.");ShowStep(StepTarget);return;}try{OpenLocal(Path.Combine(RootText(),relative));}catch(Exception ex){MessageBox.Show(this,ex.Message,"폴더 열기 오류");}}
        void OpenLocal(string path) {if(!Directory.Exists(path)){MessageBox.Show(this,"아직 만들어지지 않은 폴더입니다. 모델 준비를 먼저 실행하세요.\n"+path);return;}Process.Start(new ProcessStartInfo("explorer.exe","\""+path+"\""){UseShellExecute=true});}
        // Backend errors are English (the script must stay ASCII); show the common ones in Korean, keeping the original for support.
        static readonly string[,] Friendly = {
            {"Close RealFlight, Mission Planner and SITL first", "RealFlight · Mission Planner · SITL을 먼저 모두 종료하세요. 응답 없음 상태라면 작업 관리자에서 끝내세요."},
            {"Close Mission Planner and every SITL window first", "Mission Planner와 SITL 창을 모두 닫은 뒤 다시 누르세요('남은 SITL 창 종료'를 써도 됩니다)."},
            {"Import missing model first", "아직 Import되지 않은 기종이 있습니다. RealFlight에서 Import하거나, 그 기종의 체크를 해제한 뒤 다시 누르세요. 아무것도 바꾸지 않았습니다."},
            {"Incomplete Import", "Import가 덜 끝난 기종이 있습니다(모델 파일 일부 없음). RealFlight에서 그 기종을 다시 Import하세요."},
            {"Run RealFlight once, exit it", "선택한 문서 폴더가 없습니다. RealFlight를 한 번 실행했다가 종료한 뒤 '다시 검색'을 누르세요."},
            {"Select the exact USER DATA folder", "RealFlight.ini가 있는 '문서' 쪽 사용자 폴더를 선택하세요. 프로그램 설치 폴더가 아닙니다."},
            {"Executable edition and user-data folder do not match", "선택한 실행 파일과 문서 폴더의 RealFlight 버전이 다릅니다. 같은 버전끼리 선택하세요."},
            {"RealFlight executable not found", "RealFlight 실행 파일을 찾지 못했습니다. '다시 검색' 또는 '실행 파일 직접 선택'을 누르세요."},
            {"Linked/cloud-placeholder path refused", "OneDrive 같은 동기화 폴더나 바로가기 경로는 쓸 수 없습니다. PC에 실제로 있는 폴더를 선택하세요."},
            {"No SITL backup made by this helper", "되돌릴 SITL 백업이 없습니다. 도우미로 SITL 저장 설정을 초기화한 적이 없는 PC입니다."},
            {"No RealFlight INI reset made by this helper", "되돌릴 RealFlight 설정 백업이 없습니다. 도우미로 RF 설정을 초기화한 적이 없는 대상입니다."},
            {"No ArduPlane SITL in", "Mission Planner에 SITL 프로그램이 아직 없습니다. MP에서 Simulation → Plane을 한 번 눌러 받아 두세요(인터넷 필요)."},
            {"A SITL is already running", "SITL이 이미 실행 중입니다. 한 RealFlight에는 SITL 하나만 연결하세요. 필요하면 'SITL 종료'를 누른 뒤 다시 시작하세요."},
            {"Start RealFlight and select the aircraft first", "RealFlight를 먼저 켜고 기체를 고른 뒤 누르세요. flightaxis SITL은 RealFlight 화면의 기체를 조종합니다."},
            {"SITL exited immediately", "SITL이 켜지자마자 종료되었습니다. 'SITL 종료' 후 다시 시도하고, 계속되면 '연결 문제 해결'의 ① 진단을 보내 주세요."},
            {"Mission Planner auto-connect on UDP 14550 is turned off", "Mission Planner 자동 연결(UDP 14550)이 꺼져 있습니다. MP 연결 단추에서 TCP → 127.0.0.1 → 5760으로 연결하세요."},
            {"RealFlight is not listening on 18083", "RealFlight가 FlightAxis 포트(18083)에서 대기하지 않습니다. Settings → Physics에서 RealFlight Link = Yes인지 확인하세요."},
            {"Mission Planner was not found", "Mission Planner를 찾지 못했습니다. 직접 실행하세요."}
        };
        static string Plain(string message) {
            for(int i=0;i<Friendly.GetLength(0);i++) if(message.StartsWith(Friendly[i,0],StringComparison.Ordinal)) return Friendly[i,1];
            return message;
        }
        static string Explain(string message) {
            for(int i=0;i<Friendly.GetLength(0);i++) if(message.StartsWith(Friendly[i,0],StringComparison.Ordinal)) return Friendly[i,1]+"\n\n(원문: "+message+")";
            return message;
        }
        void Fail(Exception ex) {Append("중단: "+ex.Message);SetBusy(false,"작업 중단 · 오류와 백업 위치를 확인하세요.");MessageBox.Show(this,Explain(ex.Message)+"\n\n오류를 해결하기 전 새 파라미터를 적용하거나 비행하지 마세요.","안전하게 중단했습니다",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
        string Hash(byte[] bytes) {using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
        byte[] Embedded() {using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))using(var m=new MemoryStream()){s.CopyTo(m);return m.ToArray();}}
        string ExtractPayload() {
            byte[] data=Embedded();string dest=Path.Combine(work,"payload",Hash(data).Substring(0,16));Directory.CreateDirectory(dest);
            using(var zip=new ZipArchive(new MemoryStream(data),ZipArchiveMode.Read))foreach(var e in zip.Entries){if(e.FullName!=Path.GetFileName(e.FullName))throw new Exception("잘못된 내장 파일 경로");string file=Path.Combine(dest,e.FullName);using(var s=e.Open())using(var m=new MemoryStream()){s.CopyTo(m);byte[] content=m.ToArray();if(File.Exists(file)){if(Hash(File.ReadAllBytes(file))!=Hash(content))throw new Exception("내장 실행 스크립트가 변경되어 실행을 중단했습니다: "+file);}else{string temp=file+"."+Guid.NewGuid().ToString("N")+".tmp";File.WriteAllBytes(temp,content);try{File.Move(temp,file);}catch(IOException){if(!File.Exists(file))throw;}finally{if(File.Exists(temp))File.Delete(temp);}if(Hash(File.ReadAllBytes(file))!=Hash(content))throw new Exception("내장 실행 스크립트가 변경되어 실행을 중단했습니다: "+file);}}}
            return dest;
        }
        void VerifyPayload() {if(ExtractPayload()!=payload)throw new Exception("내장 파일 검증 오류");}
    }
}
