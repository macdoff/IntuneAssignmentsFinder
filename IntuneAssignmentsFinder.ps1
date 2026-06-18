<#
Intune Assignments Finder
PowerShell GUI tool to analyze Intune assignments through Microsoft Graph.
See README.md for usage, prerequisites, and troubleshooting.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $MaximumFunctionCount = 32768
    $MaximumVariableCount = 32768
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Data

if (-not ('IntuneDarkTabControlV3' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class IntuneDarkTabControlV3 : TabControl
{
    public Color ThemeBack { get; set; }
    public Color TabBack { get; set; }
    public Color SelectedBack { get; set; }
    public Color BorderColor { get; set; }
    public Color AccentColor { get; set; }
    public Color TextColor { get; set; }
    public Color SelectedTextColor { get; set; }
    public int CornerRadius { get; set; }

    public IntuneDarkTabControlV3()
    {
        ThemeBack = Color.FromArgb(24, 27, 31);
        TabBack = Color.FromArgb(31, 35, 40);
        SelectedBack = Color.FromArgb(54, 85, 122);
        BorderColor = Color.FromArgb(55, 62, 72);
        AccentColor = Color.FromArgb(78, 122, 170);
        TextColor = Color.FromArgb(178, 186, 196);
        SelectedTextColor = Color.White;
        CornerRadius = 8;

        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        DrawMode = TabDrawMode.OwnerDrawFixed;
        SizeMode = TabSizeMode.Fixed;
        ItemSize = new Size(138, 40);
        Padding = new Point(14, 4);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.Clear(ThemeBack);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        using (Pen divider = new Pen(BorderColor))
        {
            e.Graphics.DrawLine(divider, 0, ItemSize.Height + 1, Width, ItemSize.Height + 1);
        }

        for (int index = 0; index < TabCount; index++)
        {
            DrawTab(e.Graphics, index);
        }
    }

    protected override void OnSelectedIndexChanged(EventArgs e)
    {
        base.OnSelectedIndexChanged(e);
        Invalidate();
    }

    private void DrawTab(Graphics graphics, int index)
    {
        bool selected = index == SelectedIndex;
        Rectangle bounds = GetTabRect(index);
        bounds.Inflate(-2, -1);

        Color text = selected ? SelectedTextColor : TextColor;

        if (selected)
        {
            Rectangle selectedBack = new Rectangle(bounds.Left + 4, bounds.Top + 2, bounds.Width - 8, bounds.Height - 6);
            using (GraphicsPath path = RoundedRectangle(selectedBack, CornerRadius))
            using (SolidBrush brush = new SolidBrush(AccentColor))
            {
                graphics.FillPath(brush, path);
            }

            using (Pen accent = new Pen(Color.FromArgb(238, 232, 214), 3))
            {
                int y = selectedBack.Bottom - 5;
                int indicatorWidth = Math.Min(30, Math.Max(18, bounds.Width / 4));
                int centerX = bounds.Left + bounds.Width / 2;
                graphics.DrawLine(accent, centerX - indicatorWidth / 2, y, centerX + indicatorWidth / 2, y);
            }
        }

        Rectangle textBounds = selected ? new Rectangle(bounds.Left, bounds.Top - 3, bounds.Width, bounds.Height - 4) : bounds;
        TextRenderer.DrawText(
            graphics,
            TabPages[index].Text,
            Font,
            textBounds,
            text,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis
        );
    }

    private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int diameter = Math.Max(1, radius * 2);
        Rectangle arc = new Rectangle(bounds.X, bounds.Y, diameter, diameter);

        path.AddArc(arc, 180, 90);
        arc.X = bounds.Right - diameter;
        path.AddArc(arc, 270, 90);
        arc.Y = bounds.Bottom - diameter;
        path.AddArc(arc, 0, 90);
        arc.X = bounds.X;
        path.AddArc(arc, 90, 90);
        path.CloseFigure();

        return path;
    }
}

public class IntuneCheckedComboBoxV3 : ComboBox
{
    private CheckedListBox checkedList;
    private ToolStripDropDown dropDown;
    private ToolStripControlHost host;

    public string SingularName { get; set; }
    public string PluralName { get; set; }

    public IntuneCheckedComboBoxV3()
    {
        SingularName = "group";
        PluralName = "groups";
        DropDownStyle = ComboBoxStyle.DropDown;
        DropDownHeight = 1;
        IntegralHeight = false;
        FlatStyle = FlatStyle.Flat;

        checkedList = new CheckedListBox();
        checkedList.CheckOnClick = true;
        checkedList.BorderStyle = BorderStyle.FixedSingle;
        checkedList.IntegralHeight = false;
        checkedList.ItemHeight = 20;
        checkedList.ItemCheck += delegate
        {
            if (IsHandleCreated)
            {
                BeginInvoke((MethodInvoker)delegate
                {
                    UpdateSummaryText();
                    OnSelectedIndexChanged(EventArgs.Empty);
                });
            }
            else
            {
                UpdateSummaryText();
            }
        };

        host = new ToolStripControlHost(checkedList);
        host.AutoSize = false;
        host.Margin = Padding.Empty;
        host.Padding = Padding.Empty;

        dropDown = new ToolStripDropDown();
        dropDown.AutoSize = false;
        dropDown.Padding = Padding.Empty;
        dropDown.Margin = Padding.Empty;
        dropDown.Items.Add(host);

        KeyPress += delegate(object sender, KeyPressEventArgs e) { e.Handled = true; };
    }

    public void SetItems(string[] items)
    {
        checkedList.Items.Clear();
        if (items != null)
        {
            foreach (string item in items)
            {
                if (!string.IsNullOrWhiteSpace(item))
                {
                    checkedList.Items.Add(item, true);
                }
            }
        }
        UpdateSummaryText();
    }

    public int GetItemCount()
    {
        return checkedList.Items.Count;
    }

    public string[] GetCheckedItems()
    {
        string[] result = new string[checkedList.CheckedItems.Count];
        for (int index = 0; index < checkedList.CheckedItems.Count; index++)
        {
            result[index] = checkedList.CheckedItems[index].ToString();
        }
        return result;
    }

    public void SetCheckedItems(string[] itemsToCheck)
    {
        HashSet<string> selected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (itemsToCheck != null)
        {
            foreach (string item in itemsToCheck)
            {
                if (!string.IsNullOrWhiteSpace(item))
                {
                    selected.Add(item);
                }
            }
        }

        bool checkAll = selected.Count == 0;
        for (int index = 0; index < checkedList.Items.Count; index++)
        {
            string itemText = checkedList.Items[index].ToString();
            checkedList.SetItemChecked(index, checkAll || selected.Contains(itemText));
        }
        UpdateSummaryText();
        OnSelectedIndexChanged(EventArgs.Empty);
    }

    public void SetTheme(Color backColor, Color foreColor, Color borderColor)
    {
        BackColor = backColor;
        ForeColor = foreColor;
        checkedList.BackColor = backColor;
        checkedList.ForeColor = foreColor;
        checkedList.BorderStyle = BorderStyle.FixedSingle;
        host.BackColor = backColor;
        dropDown.BackColor = backColor;
    }

    protected override void OnDropDown(EventArgs e)
    {
        DroppedDown = false;
        ShowCheckedDropDown();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        Focus();
        ShowCheckedDropDown();
    }

    private void ShowCheckedDropDown()
    {
        if (dropDown.Visible)
        {
            return;
        }

        DroppedDown = false;

        int itemHeight = Math.Max(checkedList.ItemHeight, 20);
        int visibleItems = Math.Max(1, Math.Min(12, checkedList.Items.Count));
        int height = Math.Max(itemHeight + 2, visibleItems * itemHeight + 2);
        int width = Math.Max(Width, 260);
        checkedList.Size = new Size(width, height);
        host.Size = checkedList.Size;
        dropDown.Size = checkedList.Size;
        dropDown.Show(this, 0, Height);
    }

    private void UpdateSummaryText()
    {
        int selected = checkedList.CheckedItems.Count;
        int total = checkedList.Items.Count;
        if (total == 0)
        {
            Text = "No " + PluralName + " loaded";
        }
        else if (selected == 0)
        {
            Text = "No " + PluralName + " selected";
        }
        else if (selected == total)
        {
            Text = total + " " + (total == 1 ? SingularName : PluralName) + " selected";
        }
        else
        {
            Text = selected + " / " + total + " " + (selected == 1 ? SingularName : PluralName) + " selected";
        }
        SelectionStart = Text.Length;
    }
}

public class IntuneDarkScrollBarV1 : Control
{
    private bool dragging;
    private int dragOffset;
    private Rectangle thumbBounds;

    public Orientation Orientation { get; set; }
    public int Minimum { get; set; }
    public int Maximum { get; set; }
    public int LargeChange { get; set; }
    public int SmallChange { get; set; }
    public int Value { get; private set; }
    public Color TrackColor { get; set; }
    public Color ThumbColor { get; set; }
    public Color ThumbHoverColor { get; set; }
    public Color ThumbPressedColor { get; set; }
    public Color BorderColor { get; set; }

    public event ScrollEventHandler Scroll;

    public IntuneDarkScrollBarV1()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Orientation = System.Windows.Forms.Orientation.Vertical;
        Minimum = 0;
        Maximum = 0;
        LargeChange = 10;
        SmallChange = 1;
        TrackColor = Color.FromArgb(24, 27, 31);
        ThumbColor = Color.FromArgb(78, 122, 170);
        ThumbHoverColor = Color.FromArgb(96, 145, 198);
        ThumbPressedColor = Color.FromArgb(54, 85, 122);
        BorderColor = Color.FromArgb(55, 62, 72);
        Cursor = Cursors.Hand;
        Width = 13;
        Height = 13;
    }

    public void SetRange(int minimum, int maximum, int largeChange)
    {
        Minimum = Math.Max(0, minimum);
        Maximum = Math.Max(Minimum, maximum);
        LargeChange = Math.Max(1, largeChange);
        SetValue(Value);
        Visible = Maximum > Minimum;
        Invalidate();
    }

    public void SetValue(int value)
    {
        int newValue = Math.Max(Minimum, Math.Min(Maximum, value));
        if (newValue == Value)
        {
            return;
        }
        Value = newValue;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush track = new SolidBrush(TrackColor))
        using (Pen border = new Pen(BorderColor))
        {
            e.Graphics.FillRectangle(track, ClientRectangle);
            e.Graphics.DrawRectangle(border, 0, 0, Width - 1, Height - 1);
        }

        thumbBounds = GetThumbBounds();
        if (thumbBounds.Width <= 0 || thumbBounds.Height <= 0)
        {
            return;
        }

        Color fill = dragging ? ThumbPressedColor : (ClientRectangle.Contains(PointToClient(Cursor.Position)) ? ThumbHoverColor : ThumbColor);
        using (GraphicsPath path = RoundedRectangle(thumbBounds, 5))
        using (SolidBrush thumb = new SolidBrush(fill))
        {
            e.Graphics.FillPath(thumb, path);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left)
        {
            return;
        }

        thumbBounds = GetThumbBounds();
        int pointer = Orientation == System.Windows.Forms.Orientation.Vertical ? e.Y : e.X;
        if (thumbBounds.Contains(e.Location))
        {
            dragging = true;
            dragOffset = pointer - (Orientation == System.Windows.Forms.Orientation.Vertical ? thumbBounds.Y : thumbBounds.X);
            Capture = true;
        }
        else
        {
            int thumbStart = Orientation == System.Windows.Forms.Orientation.Vertical ? thumbBounds.Y : thumbBounds.X;
            ChangeValue(pointer < thumbStart ? -LargeChange : LargeChange, ScrollEventType.LargeIncrement);
        }
        Invalidate();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!dragging)
        {
            Invalidate();
            return;
        }

        int trackLength = Orientation == System.Windows.Forms.Orientation.Vertical ? Height : Width;
        int thumbLength = Orientation == System.Windows.Forms.Orientation.Vertical ? thumbBounds.Height : thumbBounds.Width;
        int travel = Math.Max(1, trackLength - thumbLength - 4);
        int pointer = Orientation == System.Windows.Forms.Orientation.Vertical ? e.Y : e.X;
        int position = Math.Max(2, Math.Min(trackLength - thumbLength - 2, pointer - dragOffset));
        double ratio = (double)(position - 2) / travel;
        int newValue = Minimum + (int)Math.Round(ratio * (Maximum - Minimum));
        SetValueWithEvent(newValue, ScrollEventType.ThumbTrack);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (dragging)
        {
            dragging = false;
            Capture = false;
            OnScroll(new ScrollEventArgs(ScrollEventType.EndScroll, Value, Orientation == System.Windows.Forms.Orientation.Vertical ? ScrollOrientation.VerticalScroll : ScrollOrientation.HorizontalScroll));
        }
        Invalidate();
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        base.OnMouseWheel(e);
        ChangeValue(e.Delta > 0 ? -SmallChange : SmallChange, ScrollEventType.SmallIncrement);
    }

    private Rectangle GetThumbBounds()
    {
        int trackLength = Orientation == System.Windows.Forms.Orientation.Vertical ? Height : Width;
        int trackBreadth = Orientation == System.Windows.Forms.Orientation.Vertical ? Width : Height;
        int range = Math.Max(1, Maximum - Minimum + LargeChange);
        int thumbLength = Math.Max(24, (int)Math.Round((double)LargeChange / range * Math.Max(1, trackLength - 4)));
        thumbLength = Math.Min(Math.Max(1, trackLength - 4), thumbLength);
        int travel = Math.Max(1, trackLength - thumbLength - 4);
        double ratio = Maximum == Minimum ? 0 : (double)(Value - Minimum) / (Maximum - Minimum);
        int position = 2 + (int)Math.Round(ratio * travel);
        if (Orientation == System.Windows.Forms.Orientation.Vertical)
        {
            return new Rectangle(2, position, Math.Max(1, trackBreadth - 4), thumbLength);
        }
        return new Rectangle(position, 2, thumbLength, Math.Max(1, trackBreadth - 4));
    }

    private void ChangeValue(int delta, ScrollEventType type)
    {
        SetValueWithEvent(Value + delta, type);
    }

    private void SetValueWithEvent(int value, ScrollEventType type)
    {
        int oldValue = Value;
        SetValue(value);
        if (Value != oldValue)
        {
            OnScroll(new ScrollEventArgs(type, oldValue, Value, Orientation == System.Windows.Forms.Orientation.Vertical ? ScrollOrientation.VerticalScroll : ScrollOrientation.HorizontalScroll));
        }
    }

    private void OnScroll(ScrollEventArgs e)
    {
        ScrollEventHandler handler = Scroll;
        if (handler != null)
        {
            handler(this, e);
        }
    }

    private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int diameter = Math.Max(1, radius * 2);
        Rectangle arc = new Rectangle(bounds.X, bounds.Y, diameter, diameter);
        path.AddArc(arc, 180, 90);
        arc.X = bounds.Right - diameter;
        path.AddArc(arc, 270, 90);
        arc.Y = bounds.Bottom - diameter;
        path.AddArc(arc, 0, 90);
        arc.X = bounds.X;
        path.AddArc(arc, 90, 90);
        path.CloseFigure();
        return path;
    }
}

public static class IntuneNativeThemeV1
{
    private const int EM_GETFIRSTVISIBLELINE = 0x00CE;
    private const int EM_LINESCROLL = 0x00B6;

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string appName, string partList);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

    public static void ApplyDarkScrollBars(Control control)
    {
        if (control == null)
        {
            return;
        }

        if (control.IsHandleCreated)
        {
            SetWindowTheme(control.Handle, "DarkMode_Explorer", null);
        }

        control.HandleCreated += delegate
        {
            SetWindowTheme(control.Handle, "DarkMode_Explorer", null);
        };

        foreach (Control child in control.Controls)
        {
            ApplyDarkScrollBars(child);
        }
    }

    public static int GetFirstVisibleLine(TextBoxBase control)
    {
        if (control == null || !control.IsHandleCreated)
        {
            return 0;
        }

        return SendMessage(control.Handle, EM_GETFIRSTVISIBLELINE, IntPtr.Zero, IntPtr.Zero).ToInt32();
    }

    public static void ScrollTextBox(TextBoxBase control, int columns, int lines)
    {
        if (control == null || !control.IsHandleCreated || (columns == 0 && lines == 0))
        {
            return;
        }

        SendMessage(control.Handle, EM_LINESCROLL, new IntPtr(columns), new IntPtr(lines));
    }
}
'@
}

if (-not ('IntuneNativeThemeV2' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class IntuneNativeThemeV2
{
    private const int EM_GETFIRSTVISIBLELINE = 0x00CE;
    private const int EM_LINESCROLL = 0x00B6;

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string appName, string partList);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

    public static void ApplyDarkScrollBars(Control control)
    {
        if (control == null)
        {
            return;
        }

        if (control.IsHandleCreated)
        {
            SetWindowTheme(control.Handle, "DarkMode_Explorer", null);
        }

        control.HandleCreated += delegate
        {
            SetWindowTheme(control.Handle, "DarkMode_Explorer", null);
        };

        foreach (Control child in control.Controls)
        {
            ApplyDarkScrollBars(child);
        }
    }

    public static int GetFirstVisibleLine(TextBoxBase control)
    {
        if (control == null || !control.IsHandleCreated)
        {
            return 0;
        }

        return SendMessage(control.Handle, EM_GETFIRSTVISIBLELINE, IntPtr.Zero, IntPtr.Zero).ToInt32();
    }

    public static void ScrollTextBox(TextBoxBase control, int columns, int lines)
    {
        if (control == null || !control.IsHandleCreated || (columns == 0 && lines == 0))
        {
            return;
        }

        SendMessage(control.Handle, EM_LINESCROLL, new IntPtr(columns), new IntPtr(lines));
    }
}
'@
}

if (-not ('IntuneWindowChromeV1' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class IntuneWindowChromeV1
{
    private const int WM_NCLBUTTONDOWN = 0x00A1;
    private const int HTCAPTION = 0x0002;

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

    public static void DragWindow(Form form)
    {
        if (form == null || !form.IsHandleCreated)
        {
            return;
        }

        ReleaseCapture();
        SendMessage(form.Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
    }
}
'@
}

if (-not ('IntuneWindowChromeV2' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class IntuneWindowChromeV2
{
    private const int WM_NCLBUTTONDOWN = 0x00A1;
    private const int WM_NCHITTEST = 0x0084;
    private const int HTCLIENT = 0x0001;
    private const int HTCAPTION = 0x0002;
    private const int HTLEFT = 0x000A;
    private const int HTRIGHT = 0x000B;
    private const int HTTOP = 0x000C;
    private const int HTTOPLEFT = 0x000D;
    private const int HTTOPRIGHT = 0x000E;
    private const int HTBOTTOM = 0x000F;
    private const int HTBOTTOMLEFT = 0x0010;
    private const int HTBOTTOMRIGHT = 0x0011;

    private static readonly Dictionary<IntPtr, ResizeChrome> ResizeHooks = new Dictionary<IntPtr, ResizeChrome>();

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

    public static void DragWindow(Form form)
    {
        if (form == null || !form.IsHandleCreated || form.WindowState == FormWindowState.Maximized)
        {
            return;
        }

        ReleaseCapture();
        SendMessage(form.Handle, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
    }

    public static void ResizeWindow(Form form, int hitTest)
    {
        if (form == null || !form.IsHandleCreated || form.WindowState == FormWindowState.Maximized)
        {
            return;
        }

        ReleaseCapture();
        SendMessage(form.Handle, WM_NCLBUTTONDOWN, new IntPtr(hitTest), IntPtr.Zero);
    }

    public static void EnableResize(Form form, int borderWidth)
    {
        if (form == null || !form.IsHandleCreated)
        {
            return;
        }

        if (ResizeHooks.ContainsKey(form.Handle))
        {
            return;
        }

        ResizeChrome hook = new ResizeChrome(form, Math.Max(4, borderWidth));
        ResizeHooks[form.Handle] = hook;
        form.FormClosed += delegate { ResizeHooks.Remove(form.Handle); };
    }

    private sealed class ResizeChrome : NativeWindow
    {
        private readonly Form form;
        private readonly int borderWidth;

        public ResizeChrome(Form form, int borderWidth)
        {
            this.form = form;
            this.borderWidth = borderWidth;
            AssignHandle(form.Handle);
        }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);

            if (m.Msg != WM_NCHITTEST || m.Result.ToInt32() != HTCLIENT || form.WindowState == FormWindowState.Maximized)
            {
                return;
            }

            int x = unchecked((short)((long)m.LParam & 0xFFFF));
            int y = unchecked((short)(((long)m.LParam >> 16) & 0xFFFF));
            Point clientPoint = form.PointToClient(new Point(x, y));

            bool left = clientPoint.X <= borderWidth;
            bool right = clientPoint.X >= form.ClientSize.Width - borderWidth;
            bool top = clientPoint.Y <= borderWidth;
            bool bottom = clientPoint.Y >= form.ClientSize.Height - borderWidth;

            if (left && top) m.Result = new IntPtr(HTTOPLEFT);
            else if (right && top) m.Result = new IntPtr(HTTOPRIGHT);
            else if (left && bottom) m.Result = new IntPtr(HTBOTTOMLEFT);
            else if (right && bottom) m.Result = new IntPtr(HTBOTTOMRIGHT);
            else if (left) m.Result = new IntPtr(HTLEFT);
            else if (right) m.Result = new IntPtr(HTRIGHT);
            else if (top) m.Result = new IntPtr(HTTOP);
            else if (bottom) m.Result = new IntPtr(HTBOTTOM);
        }
    }
}
'@
}

if (-not ('IntuneResizableFormV1' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;

public class IntuneResizableFormV1 : Form
{
    private const int WM_NCHITTEST = 0x0084;
    private const int HTCLIENT = 0x0001;
    private const int HTLEFT = 0x000A;
    private const int HTRIGHT = 0x000B;
    private const int HTTOP = 0x000C;
    private const int HTTOPLEFT = 0x000D;
    private const int HTTOPRIGHT = 0x000E;
    private const int HTBOTTOM = 0x000F;
    private const int HTBOTTOMLEFT = 0x0010;
    private const int HTBOTTOMRIGHT = 0x0011;

    public int ResizeBorderWidth { get; set; }

    public IntuneResizableFormV1()
    {
        ResizeBorderWidth = 8;
    }

    protected override void WndProc(ref Message m)
    {
        base.WndProc(ref m);

        if (m.Msg != WM_NCHITTEST || m.Result.ToInt32() != HTCLIENT || WindowState == FormWindowState.Maximized)
        {
            return;
        }

        int x = unchecked((short)((long)m.LParam & 0xFFFF));
        int y = unchecked((short)(((long)m.LParam >> 16) & 0xFFFF));
        Point clientPoint = PointToClient(new Point(x, y));
        int grip = Math.Max(4, ResizeBorderWidth);

        bool left = clientPoint.X <= grip;
        bool right = clientPoint.X >= ClientSize.Width - grip;
        bool top = clientPoint.Y <= grip;
        bool bottom = clientPoint.Y >= ClientSize.Height - grip;

        if (left && top) m.Result = new IntPtr(HTTOPLEFT);
        else if (right && top) m.Result = new IntPtr(HTTOPRIGHT);
        else if (left && bottom) m.Result = new IntPtr(HTBOTTOMLEFT);
        else if (right && bottom) m.Result = new IntPtr(HTBOTTOMRIGHT);
        else if (left) m.Result = new IntPtr(HTLEFT);
        else if (right) m.Result = new IntPtr(HTRIGHT);
        else if (top) m.Result = new IntPtr(HTTOP);
        else if (bottom) m.Result = new IntPtr(HTBOTTOM);
    }
}
'@
}

if (-not ('IntuneShellIdentityV1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class IntuneShellIdentityV1
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appID);

    public static void SetAppUserModelId(string appId)
    {
        if (!string.IsNullOrWhiteSpace(appId))
        {
            SetCurrentProcessExplicitAppUserModelID(appId);
        }
    }
}
'@
}

if (-not ('IntuneTaskbarInfoV2' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;

public static class IntuneTaskbarInfoV2
{
    private const int ABM_GETSTATE = 0x00000004;
    private const int ABM_GETTASKBARPOS = 0x00000005;
    private const int ABS_AUTOHIDE = 0x00000001;
    private const int ABE_LEFT = 0;
    private const int ABE_TOP = 1;
    private const int ABE_RIGHT = 2;
    private const int ABE_BOTTOM = 3;

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public int uCallbackMessage;
        public int uEdge;
        public RECT rc;
        public IntPtr lParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [DllImport("shell32.dll")]
    private static extern IntPtr SHAppBarMessage(int dwMessage, ref APPBARDATA pData);

    public static Rectangle GetMaximizedBounds(Rectangle workingArea, Rectangle screenBounds)
    {
        Rectangle result = workingArea;
        APPBARDATA data = new APPBARDATA();
        data.cbSize = Marshal.SizeOf(typeof(APPBARDATA));

        int state = SHAppBarMessage(ABM_GETSTATE, ref data).ToInt32();
        if ((state & ABS_AUTOHIDE) == 0)
        {
            return result;
        }

        data = new APPBARDATA();
        data.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
        if (SHAppBarMessage(ABM_GETTASKBARPOS, ref data) == IntPtr.Zero)
        {
            return LeaveBottomTriggerPixel(result);
        }

        Rectangle taskbarBounds = Rectangle.FromLTRB(data.rc.left, data.rc.top, data.rc.right, data.rc.bottom);
        if (!screenBounds.IntersectsWith(taskbarBounds))
        {
            return result;
        }

        switch (data.uEdge)
        {
            case ABE_LEFT:
                return new Rectangle(result.Left + 1, result.Top, Math.Max(1, result.Width - 1), result.Height);
            case ABE_TOP:
                return new Rectangle(result.Left, result.Top + 1, result.Width, Math.Max(1, result.Height - 1));
            case ABE_RIGHT:
                return new Rectangle(result.Left, result.Top, Math.Max(1, result.Width - 1), result.Height);
            case ABE_BOTTOM:
                return LeaveBottomTriggerPixel(result);
            default:
                return result;
        }
    }

    private static Rectangle LeaveBottomTriggerPixel(Rectangle bounds)
    {
        return new Rectangle(bounds.Left, bounds.Top, bounds.Width, Math.Max(1, bounds.Height - 1));
    }
}
'@
}

$script:RequiredGraphModule = 'Microsoft.Graph.Authentication'
$script:GraphScopes = @(
    'Group.Read.All',
    'Directory.Read.All',
    'DeviceManagementApps.Read.All',
    'DeviceManagementConfiguration.Read.All',
    'DeviceManagementManagedDevices.Read.All',
    'DeviceManagementServiceConfig.Read.All'
)
$script:GraphTenantId = 'organizations'
$script:DefaultGroupListPath = 'C:\Temp\ListGroups.txt'
$script:ResultsTable = $null
$script:BindingSource = $null
$script:IsConnected = $false
$script:ConnectedAccount = ''
$script:ConnectedTenantId = ''
$script:VerboseLog = $true
$script:form = $null
$script:txtLog = $null
$script:lblStatus = $null
$script:progressBar = $null
$script:btnConnect = $null
$script:titleBar = $null
$script:statusBar = $null
$script:AppIcon = $null
$script:AppIconBitmap = $null
$script:lblConnectedAccount = $null
$script:lblConnectedAccountValue = $null
$script:metricsPanel = $null
$script:metricValueLabels = @{}
$script:txtResultFilter = $null
$script:cboGroupFilter = $null
$script:cboCategoryFilter = $null
$script:cboIntentFilter = $null
$script:cboScopeFilter = $null
$script:filterPanel = $null
$script:splitResults = $null
$script:analysisTabs = $null
$script:UpdateHeaderLayout = $null
$script:AnalysisButtons = @()
$script:txtCustomGroup = $null
$script:txtDeviceSearch = $null
$script:txtUserMail = $null
$script:btnAnalyzeDefault = $null
$script:btnAnalyzeCustom = $null
$script:btnAnalyzeDevice = $null
$script:btnAnalyzeUser = $null
$script:btnReloadDefaultGroups = $null
$script:btnExportCsv = $null
$script:btnCancelAnalysis = $null
$script:cboDefaultGroups = $null
$script:grid = $null
$script:IsAnalysisRunning = $false
$script:CancelRequested = $false
function Write-UiLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Verbose')][string]$Level = 'Info'
    )

    if ($Level -eq 'Verbose' -and -not $script:VerboseLog) {
        return
    }

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Message

    if ($script:txtLog) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.ScrollToCaret()
    }
}

function Show-UiError {
    param(
        [Parameter(Mandatory = $true)]$ErrorRecord,
        [string]$Title = 'Error'
    )

    $message = $ErrorRecord.Exception.Message
    $line = $ErrorRecord.InvocationInfo.ScriptLineNumber
    $command = $ErrorRecord.InvocationInfo.Line

    if ($line) {
        Write-UiLog -Message ("{0} (line {1})" -f $message, $line) -Level Error
    }
    else {
        Write-UiLog -Message $message -Level Error
    }

    if (-not [string]::IsNullOrWhiteSpace($command)) {
        Write-UiLog -Message ("Command: {0}" -f $command.Trim()) -Level Verbose
    }

    $display = $message
    if ($line) {
        $display = "{0}`r`n`r`nLine: {1}" -f $message, $line
    }

    [System.Windows.Forms.MessageBox]::Show($display, $Title, 'OK', 'Error') | Out-Null
}

function Set-UiStatus {
    param(
        [string]$Text,
        [int]$Percent = -1
    )

    if ($script:lblStatus) {
        $script:lblStatus.Text = $Text
    }

    if ($script:progressBar -and $Percent -ge 0) {
        if ($Percent -lt 0) { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }
        $script:progressBar.Value = $Percent
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Set-CancelAnalysisButtonState {
    param(
        [bool]$Visible,
        [bool]$Enabled = $true
    )

    if (-not $script:btnCancelAnalysis) { return }

    $script:btnCancelAnalysis.Visible = $Visible
    $script:btnCancelAnalysis.Enabled = $Enabled
}

function Start-AnalysisRun {
    $script:IsAnalysisRunning = $true
    $script:CancelRequested = $false
    Set-AnalysisButtonsEnabled -Enabled $false
    Set-CancelAnalysisButtonState -Visible $true -Enabled $true
}

function Stop-AnalysisRun {
    $script:IsAnalysisRunning = $false
    $script:CancelRequested = $false
    Set-CancelAnalysisButtonState -Visible $false -Enabled $false
    Set-AnalysisButtonsEnabled -Enabled $script:IsConnected
}

function Request-AnalysisCancellation {
    if (-not $script:IsAnalysisRunning) { return }

    $script:CancelRequested = $true
    Set-CancelAnalysisButtonState -Visible $true -Enabled $false
    Set-UiStatus -Text 'Cancellation requested...' -Percent -1
    Write-UiLog -Message 'Cancellation requested by user.' -Level Warn
}

function Test-AnalysisCancellation {
    [System.Windows.Forms.Application]::DoEvents()

    if ($script:CancelRequested) {
        throw [System.OperationCanceledException]::new('Analysis cancelled by user.')
    }
}

function Handle-AnalysisException {
    param(
        [Parameter(Mandatory = $true)]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$StatusText
    )

    if ($ErrorRecord.Exception -is [System.OperationCanceledException]) {
        Write-UiLog -Message 'Analysis cancelled.' -Level Warn
        Set-UiStatus -Text 'Analysis cancelled.' -Percent 0
        return
    }

    Show-UiError -ErrorRecord $ErrorRecord -Title $Title
    Set-UiStatus -Text $StatusText -Percent 0
}

function Escape-ODataString {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Get-ObjectValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        foreach ($key in $InputObject.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $InputObject[$key]
            }
        }
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }

    $additional = $InputObject.PSObject.Properties['AdditionalProperties']
    if ($additional -and $additional.Value -and $additional.Value -is [System.Collections.IDictionary]) {
        $keys = @($additional.Value.Keys)
        if ($keys -contains $Name) {
            return $additional.Value[$Name]
        }
    }

    return $null
}

function ConvertTo-CellText {
    param($Value)

    if ($null -eq $Value) { return '' }

    if ($Value -is [string]) { return $Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $parts = foreach ($key in $Value.Keys) {
            '{0}={1}' -f $key, (ConvertTo-CellText -Value $Value[$key])
        }
        return [string]($parts -join '; ')
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = foreach ($item in $Value) {
            ConvertTo-CellText -Value $item
        }
        return [string]($items -join ', ')
    }

    return [string]$Value
}

function ConvertTo-ScopeResultText {
    param(
        [string]$MatchKind,
        [string]$AssignmentType
    )

    $isExclusion = ($MatchKind -match '(?i)exclusion|excluded|exclude|exclu') -or ($AssignmentType -match '(?i)exclusion|exclude')
    if ($isExclusion) {
        if ($MatchKind -match '(?i)device') { return 'Excluded via device group' }
        if ($MatchKind -match '(?i)user') { return 'Excluded via user group' }
        return 'Excluded by group'
    }

    if ($MatchKind -match '(?i)all devices') { return 'Included: all devices' }
    if ($MatchKind -match '(?i)all users') { return 'Included: all users' }
    if ($MatchKind -match '(?i)device') { return 'Included via device group' }
    if ($MatchKind -match '(?i)user') { return 'Included via user group' }
    if ($MatchKind -match '(?i)direct|groupid') { return 'Included by group' }

    return 'Included'
}

function Get-TargetDetails {
    param($Target)

    Test-AnalysisCancellation

    if ($null -eq $Target) {
        return [PSCustomObject]@{
            GroupId = ''
            AssignmentType = ''
            FilterId = ''
            FilterMode = ''
        }
    }

    $groupId = Get-ObjectValue -InputObject $Target -Name 'groupId'
    if ([string]::IsNullOrWhiteSpace([string]$groupId)) {
        $groupId = Get-ObjectValue -InputObject $Target -Name 'targetGroupId'
    }
    if ([string]::IsNullOrWhiteSpace([string]$groupId)) {
        $groupId = Get-ObjectValue -InputObject $Target -Name 'entraObjectId'
    }
    $odataType = Get-ObjectValue -InputObject $Target -Name '@odata.type'
    $deviceAndAppManagementAssignmentFilterId = Get-ObjectValue -InputObject $Target -Name 'deviceAndAppManagementAssignmentFilterId'
    $deviceAndAppManagementAssignmentFilterType = Get-ObjectValue -InputObject $Target -Name 'deviceAndAppManagementAssignmentFilterType'

    if ([string]::IsNullOrWhiteSpace([string]$odataType)) {
        $odataType = $Target.GetType().Name
    }

    [PSCustomObject]@{
        GroupId = ConvertTo-CellText -Value $groupId
        AssignmentType = ConvertTo-CellText -Value $odataType
        FilterId = ConvertTo-CellText -Value $deviceAndAppManagementAssignmentFilterId
        FilterMode = ConvertTo-CellText -Value $deviceAndAppManagementAssignmentFilterType
    }
}

function Get-AssignmentTargetDetails {
    param($Assignment)

    return Get-TargetDetails -Target (Get-AssignmentTargetObject -Assignment $Assignment)
}

function Get-AssignmentTargetObject {
    param($Assignment)

    $target = Get-ObjectValue -InputObject $Assignment -Name 'target'
    if ($target) {
        return $target
    }

    return $Assignment
}

function New-ResultTable {
    $table = New-Object System.Data.DataTable 'IntuneAssignments'
    foreach ($columnName in @(
        'Group',
        'Category',
        'Name',
        'Intent',
        'Filter',
        'Filter mode',
        'Match',
        'Type',
        'Platform',
        'Object ID',
        'Assignment ID',
        'Group ID',
        'Assignment type',
        'Details'
    )) {
        [void]$table.Columns.Add($columnName, [string])
    }
    return ,$table
}

function Test-RequiredModules {
    [CmdletBinding()]
    param()

    Set-UiStatus -Text "Checking module $($script:RequiredGraphModule)..." -Percent 5
    Write-UiLog -Message "Checking module $($script:RequiredGraphModule)." -Level Verbose

    $module = Get-Module -ListAvailable -Name $script:RequiredGraphModule | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $module) {
        Write-UiLog -Message "Module $($script:RequiredGraphModule) missing. Automatic installation is not performed." -Level Warn
        [System.Windows.Forms.MessageBox]::Show(
            "The required PowerShell module is not installed:`r`n`r`n$($script:RequiredGraphModule)`r`n`r`nInstall it with one of these commands, then restart the tool:`r`n`r`nInstall-Module $($script:RequiredGraphModule) -Scope CurrentUser`r`nInstall-Module $($script:RequiredGraphModule) -Scope AllUsers",
            'Missing PowerShell module',
            'OK',
            'Warning'
        ) | Out-Null
        throw "Microsoft Graph Authentication module is required but not installed. Install-Module $($script:RequiredGraphModule) -Scope CurrentUser"
    }

    Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction SilentlyContinue

    $loadedGraphAuthAssemblies = @(
        [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.FullName -like 'Microsoft.Graph.Authentication*' -or $_.FullName -like 'Microsoft.Graph.PowerShell.Authentication*' }
    )

    $blockedAssembly = $loadedGraphAuthAssemblies | Where-Object { $_.FullName -match 'Version=2\.37\.0\.0' } | Select-Object -First 1
    if ($blockedAssembly) {
        throw "Microsoft Graph Authentication assembly 2.37.0 is already loaded in this PowerShell process and cannot be unloaded. Fully close this terminal/VS Code, open a new PowerShell console with -NoProfile, then run the script again."
    }

    Set-UiStatus -Text "Importing module $($script:RequiredGraphModule)..." -Percent 10
    Write-UiLog -Message "Importing module $($script:RequiredGraphModule)." -Level Verbose

    try {
        Import-Module $script:RequiredGraphModule -RequiredVersion $module.Version -Force -ErrorAction Stop
        Write-UiLog -Message "Module $($script:RequiredGraphModule) imported in version $($module.Version)." -Level Info
    }
    catch {
        throw "Unable to import module $($script:RequiredGraphModule). Detail: $($_.Exception.Message)"
    }

    $requiredCommands = @(
        'Connect-MgGraph',
        'Disconnect-MgGraph',
        'Get-MgContext',
        'Invoke-MgGraphRequest'
    )

    $missingCommands = @($requiredCommands | Where-Object { -not (Get-Command $_ -ListImported -ErrorAction SilentlyContinue) })
    if ($missingCommands.Count -gt 0) {
        throw "Some Microsoft Graph cmdlets are missing after importing $($script:RequiredGraphModule): $($missingCommands -join ', '). Update or reinstall the module, then run the tool again."
    }

    $authAssemblies = @(
        [AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.FullName -like 'Microsoft.Graph.Authentication*' } |
            ForEach-Object { $_.FullName }
    )
    foreach ($assemblyName in $authAssemblies) {
        Write-UiLog -Message "Assembly loaded : $assemblyName" -Level Verbose
    }
}

function Test-GraphScopesGranted {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $grantedScopes = @($Context.Scopes | ForEach-Object { [string]$_ })
    $missingScopes = @($script:GraphScopes | Where-Object { $grantedScopes -notcontains $_ })

    if ($missingScopes.Count -gt 0) {
        throw "Graph connected, but these required delegated scopes were not granted in this tenant: $($missingScopes -join ', '). Ask a tenant admin to grant consent for the Microsoft Graph PowerShell app, then connect again."
    }
}

function Test-GraphTokenReady {
    [CmdletBinding()]
    param()

    try {
        Invoke-MgGraphRequest -Method GET -Uri "/v1.0/organization?`$select=id,displayName" -ErrorAction Stop | Out-Null
        Write-UiLog -Message 'Graph token verified with a lightweight organization request.' -Level Verbose
    }
    catch {
        throw "Graph sign-in completed, but token acquisition for requests failed. This usually means tenant consent, Conditional Access, or cached account selection is still required. Detail: $($_.Exception.Message)"
    }
}

function Connect-Graph {
    [CmdletBinding()]
    param()

    Test-RequiredModules

    Set-UiStatus -Text 'Connecting to Microsoft Graph...' -Percent 20
    Write-UiLog -Message 'Opening Microsoft Graph connection.' -Level Info
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

    try {
        $wamMessage = 'Sign in by Web Account Manager (WAM) is enabled by default on Windows. If using an embedded terminal, the interactive browser window may be hidden behind other windows.'
        Write-Host $wamMessage
        Write-UiLog -Message $wamMessage -Level Info
        Connect-MgGraph -Scopes $script:GraphScopes -TenantId $script:GraphTenantId -ContextScope Process -NoWelcome -ErrorAction Stop
    }
    catch {
        $message = ($_ | Out-String)
        if ($message -match 'window handle|parent-window-handles|InteractiveBrowserCredential') {
            Write-UiLog -Message "Interactive sign-in cannot open from this window. Switching to device code mode." -Level Warn
            [System.Windows.Forms.MessageBox]::Show(
                "Interactive browser sign-in cannot open from this window.`r`n`r`nThe script will use device code mode. Copy the code displayed in the PowerShell console, then complete sign-in in the browser.",
                'Graph connection - device code',
                'OK',
                'Information'
            ) | Out-Null
            Connect-MgGraph -Scopes $script:GraphScopes -TenantId $script:GraphTenantId -UseDeviceCode -ContextScope Process -NoWelcome -ErrorAction Stop
        }
        else {
            if ($message -match 'RefreshCacheAsync|Microsoft.Graph.Authentication.Core|does not have an implementation') {
                Write-UiLog -Message "Graph authentication cache error. Trying device code mode with process-scoped context." -Level Warn
                try {
                    [System.Windows.Forms.MessageBox]::Show(
                        "The local Graph authentication cache returned an error.`r`n`r`nThe script will try device code sign-in with context limited to this session.",
                        'Graph connection - device code',
                        'OK',
                        'Information'
                    ) | Out-Null
                    Connect-MgGraph -Scopes $script:GraphScopes -TenantId $script:GraphTenantId -UseDeviceCode -ContextScope Process -NoWelcome -ErrorAction Stop
                }
                catch {
                    throw "Microsoft Graph Authentication version conflict detected. Close all PowerShell consoles, run the tool with PowerShell 7 if possible, then try again. If the error persists, update or reinstall the authentication module: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber"
                }
            }
            else {
                throw
            }
        }
    }

    $context = Get-MgContext
    if (-not $context) {
        throw 'Graph connection not established.'
    }

    Test-GraphScopesGranted -Context $context
    Test-GraphTokenReady

    $script:IsConnected = $true
    $script:ConnectedAccount = [string]$context.Account
    $script:ConnectedTenantId = [string]$context.TenantId
    Set-ConnectedAccountDisplay -Account $script:ConnectedAccount
    Update-GraphConnectionButtonStyle -State Connected
    Set-UiStatus -Text "Connected: $($script:ConnectedAccount)" -Percent 100
    Write-UiLog -Message "Connected to Graph with account $($script:ConnectedAccount), tenant $($script:ConnectedTenantId)." -Level Info
}

function Disconnect-GraphSession {
    [CmdletBinding()]
    param()

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-UiLog -Message "Graph disconnect returned an error: $($_.Exception.Message)" -Level Warn
    }

    $script:IsConnected = $false
    $script:ConnectedAccount = ''
    $script:ConnectedTenantId = ''
    Set-ConnectedAccountDisplay
    Set-AnalysisButtonsEnabled -Enabled $false
    Update-GraphConnectionButtonStyle -State Disconnected
    Set-UiStatus -Text 'Graph disconnected.' -Percent 0
    Write-UiLog -Message 'Disconnected from Microsoft Graph.' -Level Info
}

function Test-GraphConnectionForAnalysis {
    [CmdletBinding()]
    param()

    if (-not $script:IsConnected) {
        [System.Windows.Forms.MessageBox]::Show('Connect to Microsoft Graph first.', 'Connection required', 'OK', 'Warning') | Out-Null
        return $false
    }

    try {
        $context = Get-MgContext -ErrorAction Stop
    }
    catch {
        $context = $null
    }

    if (-not $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
        $script:IsConnected = $false
        $script:ConnectedAccount = ''
        $script:ConnectedTenantId = ''
        Set-ConnectedAccountDisplay
        Set-AnalysisButtonsEnabled -Enabled $false
        Update-GraphConnectionButtonStyle -State Disconnected
        Set-UiStatus -Text 'Graph session expired. Reconnect required.' -Percent 0
        Write-UiLog -Message 'Graph session is no longer available. Reconnect before analysis.' -Level Warn
        [System.Windows.Forms.MessageBox]::Show('The Microsoft Graph session is no longer available. Click Graph connection, then launch the analysis again.', 'Connection required', 'OK', 'Warning') | Out-Null
        return $false
    }

    return $true
}

function Get-EntraGroupByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $safeName = Escape-ODataString -Value $DisplayName.Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return @()
    }

    Write-UiLog -Message "Searching Entra ID group : $DisplayName" -Level Info

    try {
        $exactFilter = [System.Uri]::EscapeDataString("displayName eq '$safeName'")
        $exact = @(Invoke-GraphGetAllPages -Uri "/v1.0/groups?`$filter=$exactFilter&`$select=id,displayName,mail,mailNickname&`$top=999")
        if ($exact.Count -gt 0) { return $exact }
    }
    catch {
        Write-UiLog -Message "Exact search failed, trying startswith. Detail: $($_.Exception.Message)" -Level Warn
    }

    try {
        $startsWithFilter = [System.Uri]::EscapeDataString("startswith(displayName,'$safeName')")
        return @(Invoke-GraphGetAllPages -Uri "/v1.0/groups?`$filter=$startsWithFilter&`$select=id,displayName,mail,mailNickname&`$top=999")
    }
    catch {
        throw "Error while searching group '$DisplayName'. Detail: $($_.Exception.Message)"
    }
}

function Select-EntraGroup {
    param(
        [Parameter(Mandatory = $true)][array]$Groups
    )

    if ($Groups.Count -eq 1) {
        return $Groups[0]
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Group selection'
    $dialog.StartPosition = 'CenterParent'
    $dialog.Size = New-Object System.Drawing.Size(720, 420)
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $dialog.FormBorderStyle = 'FixedDialog'

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Multiple groups match. Select the one to analyze:'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 14)
    $dialog.Controls.Add($label)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(12, 42)
    $list.Size = New-Object System.Drawing.Size(680, 270)
    $list.DisplayMember = 'Display'
    foreach ($group in $Groups) {
        [void]$list.Items.Add([PSCustomObject]@{
            Display = ("{0} | {1}" -f $group.DisplayName, $group.Id)
            Group = $group
        })
    }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    $dialog.Controls.Add($list)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Analyze'
    $ok.Location = New-Object System.Drawing.Point(512, 330)
    $ok.Size = New-Object System.Drawing.Size(86, 30)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Set-RoundedButtonStyle -Button $ok
    $dialog.AcceptButton = $ok
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(606, 330)
    $cancel.Size = New-Object System.Drawing.Size(86, 30)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Set-RoundedButtonStyle -Button $cancel -BackColor ((Get-DarkTheme).Secondary)
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)

    Set-DarkControlStyle -Control $dialog -Theme (Get-DarkTheme)

    if ($dialog.ShowDialog($script:form) -eq [System.Windows.Forms.DialogResult]::OK -and $list.SelectedItem) {
        return $list.SelectedItem.Group
    }

    return $null
}

function Invoke-GraphGetAllPages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri
    )

    $items = @()
    $nextUri = $Uri
    while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
        Test-AnalysisCancellation
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextUri -ErrorAction Stop
        Test-AnalysisCancellation
        $value = Get-ObjectValue -InputObject $response -Name 'value'
        if ($value) {
            $items += @($value)
        }

        $nextUri = [string](Get-ObjectValue -InputObject $response -Name '@odata.nextLink')
    }

    return $items
}

function Get-ManagedDeviceDisplayText {
    param($Device)

    $deviceName = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $Device -Name 'deviceName')
    $serial = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $Device -Name 'serialNumber')
    $user = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $Device -Name 'userPrincipalName')
    $id = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $Device -Name 'id')

    return "{0} | Serial: {1} | User: {2} | ID: {3}" -f $deviceName, $serial, $user, $id
}

function Get-ManagedDevicesBySearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SearchText
    )

    $search = $SearchText.Trim()
    if ([string]::IsNullOrWhiteSpace($search)) {
        return @()
    }

    Write-UiLog -Message "Searching Intune device : $search" -Level Info

    $safe = Escape-ODataString -Value $search
    $isGuid = $false
    $parsedGuid = [guid]::Empty
    $isGuid = [guid]::TryParse($search, [ref]$parsedGuid)

    $filters = @(
        "deviceName eq '$safe'",
        "serialNumber eq '$safe'",
        "startswith(deviceName,'$safe')",
        "contains(deviceName,'$safe')"
    )

    if ($isGuid) {
        $filters += @(
            "id eq '$safe'",
            "azureADDeviceId eq '$safe'",
            "azureAdDeviceId eq '$safe'"
        )
    }

    $devices = @()
    foreach ($filter in $filters) {
        try {
            $encodedFilter = [System.Uri]::EscapeDataString($filter)
            $uri = "/beta/deviceManagement/managedDevices?`$filter=$encodedFilter&`$top=50"
            $devices += @(Invoke-GraphGetAllPages -Uri $uri)
        }
        catch {
            Write-UiLog -Message "Device search ignored for filter '$filter' : $($_.Exception.Message)" -Level Verbose
        }
    }

    if ($devices.Count -eq 0) {
        try {
            Write-UiLog -Message "No direct Intune result, trying via the Entra ID device." -Level Verbose
            $directoryFilters = @(
                "displayName eq '$safe'",
                "startswith(displayName,'$safe')"
            )

            if ($isGuid) {
                $directoryFilters += "deviceId eq '$safe'"
                $directoryFilters += "id eq '$safe'"
            }

            $directoryDevices = @()
            foreach ($directoryFilter in $directoryFilters) {
                try {
                    $encodedDirectoryFilter = [System.Uri]::EscapeDataString($directoryFilter)
                    $directoryDevices += @(Invoke-GraphGetAllPages -Uri "/v1.0/devices?`$filter=$encodedDirectoryFilter&`$select=id,displayName,deviceId&`$top=50")
                }
                catch {
                    Write-UiLog -Message "Entra device search ignored for filter '$directoryFilter' : $($_.Exception.Message)" -Level Verbose
                }
            }

            foreach ($directoryDevice in $directoryDevices) {
                $directoryDeviceId = [string](Get-ObjectValue -InputObject $directoryDevice -Name 'deviceId')
                if (-not [string]::IsNullOrWhiteSpace($directoryDeviceId)) {
                    $safeDirectoryDeviceId = Escape-ODataString -Value $directoryDeviceId
                    $encodedManagedFilter = [System.Uri]::EscapeDataString("azureADDeviceId eq '$safeDirectoryDeviceId'")
                    $devices += @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/managedDevices?`$filter=$encodedManagedFilter&`$top=50")
                }
            }
        }
        catch {
            Write-UiLog -Message "Unable to search device via Entra : $($_.Exception.Message)" -Level Verbose
        }
    }

    if ($devices.Count -eq 0) {
        try {
            Write-UiLog -Message "No filtered result, trying local search in Intune devices." -Level Verbose
            $wildcardSearch = [System.Management.Automation.WildcardPattern]::Escape($search)
            $candidateDevices = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/managedDevices?`$top=999")
            Write-UiLog -Message "Intune devices read for local search : $($candidateDevices.Count)." -Level Verbose
            $devices += @($candidateDevices | Where-Object {
                $id = [string](Get-ObjectValue -InputObject $_ -Name 'id')
                $deviceName = [string](Get-ObjectValue -InputObject $_ -Name 'deviceName')
                $serialNumber = [string](Get-ObjectValue -InputObject $_ -Name 'serialNumber')
                $userPrincipalName = [string](Get-ObjectValue -InputObject $_ -Name 'userPrincipalName')
                $azureAdDeviceId = [string](Get-ObjectValue -InputObject $_ -Name 'azureADDeviceId')
                if ([string]::IsNullOrWhiteSpace($azureAdDeviceId)) {
                    $azureAdDeviceId = [string](Get-ObjectValue -InputObject $_ -Name 'azureAdDeviceId')
                }

                $id -eq $search -or
                $azureAdDeviceId -eq $search -or
                $deviceName -like "*$wildcardSearch*" -or
                $serialNumber -eq $search -or
                $userPrincipalName -like "*$wildcardSearch*"
            })
        }
        catch {
            Write-UiLog -Message "Unable to run local device search : $($_.Exception.Message)" -Level Verbose
        }
    }

    $seen = @{}
    $unique = @()
    foreach ($device in $devices) {
        $id = [string](Get-ObjectValue -InputObject $device -Name 'id')
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $seen.ContainsKey($id)) {
            $seen[$id] = $true
            $unique += $device
        }
    }

    return $unique
}

function Select-ManagedDevice {
    param(
        [Parameter(Mandatory = $true)][array]$Devices
    )

    if ($Devices.Count -eq 1) {
        return $Devices[0]
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Device selection'
    $dialog.StartPosition = 'CenterParent'
    $dialog.Size = New-Object System.Drawing.Size(880, 420)
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $dialog.FormBorderStyle = 'FixedDialog'

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Multiple devices match. Select the one to analyze:'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 14)
    $dialog.Controls.Add($label)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(12, 42)
    $list.Size = New-Object System.Drawing.Size(840, 270)
    $list.DisplayMember = 'Display'
    foreach ($device in $Devices) {
        [void]$list.Items.Add([PSCustomObject]@{
            Display = Get-ManagedDeviceDisplayText -Device $device
            Device = $device
        })
    }
    if ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
    $dialog.Controls.Add($list)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Analyze'
    $ok.Location = New-Object System.Drawing.Point(672, 330)
    $ok.Size = New-Object System.Drawing.Size(86, 30)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Set-RoundedButtonStyle -Button $ok
    $dialog.AcceptButton = $ok
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.Location = New-Object System.Drawing.Point(766, 330)
    $cancel.Size = New-Object System.Drawing.Size(86, 30)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Set-RoundedButtonStyle -Button $cancel -BackColor ((Get-DarkTheme).Secondary)
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)

    Set-DarkControlStyle -Control $dialog -Theme (Get-DarkTheme)

    if ($dialog.ShowDialog($script:form) -eq [System.Windows.Forms.DialogResult]::OK -and $list.SelectedItem) {
        return $list.SelectedItem.Device
    }

    return $null
}

function Resolve-DirectoryDeviceByManagedDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice
    )

    $azureAdDeviceId = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'azureADDeviceId')
    if ([string]::IsNullOrWhiteSpace($azureAdDeviceId)) {
        $azureAdDeviceId = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'azureAdDeviceId')
    }

    if ([string]::IsNullOrWhiteSpace($azureAdDeviceId)) {
        return $null
    }

    $filter = [System.Uri]::EscapeDataString("deviceId eq '$azureAdDeviceId'")
    $uri = "/v1.0/devices?`$filter=$filter&`$select=id,displayName,deviceId"
    $devices = @(Invoke-GraphGetAllPages -Uri $uri)
    if ($devices.Count -gt 0) {
        return $devices[0]
    }

    return $null
}

function Get-TransitiveGroupsForDirectoryDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryDevice
    )

    $directoryDeviceId = [string](Get-ObjectValue -InputObject $DirectoryDevice -Name 'id')
    if ([string]::IsNullOrWhiteSpace($directoryDeviceId)) {
        return @{}
    }

    Write-UiLog -Message "Reading transitive groups for Entra ID device $directoryDeviceId." -Level Info

    $uri = "/v1.0/devices/$directoryDeviceId/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName&`$top=999"
    $groups = @(Invoke-GraphGetAllPages -Uri $uri)

    $map = @{}
    foreach ($group in $groups) {
        $id = [string](Get-ObjectValue -InputObject $group -Name 'id')
        $displayName = [string](Get-ObjectValue -InputObject $group -Name 'displayName')
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $map.ContainsKey($id)) {
            $map[$id] = $displayName
        }
    }

    return $map
}

function Resolve-DirectoryUserByMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Mail
    )

    $mailValue = $Mail.Trim()
    if ([string]::IsNullOrWhiteSpace($mailValue)) {
        return $null
    }

    Write-UiLog -Message "Searching Entra ID user : $mailValue" -Level Info

    $safeMail = Escape-ODataString -Value $mailValue
    $filters = @(
        "userPrincipalName eq '$safeMail' or mail eq '$safeMail'",
        "userPrincipalName eq '$safeMail'",
        "mail eq '$safeMail'"
    )

    foreach ($filter in $filters) {
        try {
            $encodedFilter = [System.Uri]::EscapeDataString($filter)
            $uri = "/v1.0/users?`$filter=$encodedFilter&`$select=id,displayName,userPrincipalName,mail&`$top=10"
            $users = @(Invoke-GraphGetAllPages -Uri $uri)
            if ($users.Count -gt 0) {
                return $users[0]
            }
        }
        catch {
            Write-UiLog -Message "User search ignored for filter '$filter' : $($_.Exception.Message)" -Level Verbose
        }
    }

    try {
        $escapedPath = [System.Uri]::EscapeDataString($mailValue)
        $user = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/users/$escapedPath?`$select=id,displayName,userPrincipalName,mail" -ErrorAction Stop
        if ($user) {
            return $user
        }
    }
    catch {
        Write-UiLog -Message "Direct user search ignored for '$mailValue' : $($_.Exception.Message)" -Level Verbose
    }

    return $null
}

function Get-DirectoryUserDisplayText {
    param($User)

    $displayName = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $User -Name 'displayName')
    $upn = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $User -Name 'userPrincipalName')
    $mail = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $User -Name 'mail')
    $id = ConvertTo-CellText -Value (Get-ObjectValue -InputObject $User -Name 'id')

    return "{0} | UPN: {1} | Mail: {2} | ID: {3}" -f $displayName, $upn, $mail, $id
}

function Get-TransitiveGroupsForDirectoryUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser
    )

    $directoryUserId = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'id')
    if ([string]::IsNullOrWhiteSpace($directoryUserId)) {
        return @{}
    }

    Write-UiLog -Message "Reading transitive groups for Entra ID user $directoryUserId." -Level Info

    $uri = "/v1.0/users/$directoryUserId/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName&`$top=999"
    $groups = @(Invoke-GraphGetAllPages -Uri $uri)

    $map = @{}
    foreach ($group in $groups) {
        $id = [string](Get-ObjectValue -InputObject $group -Name 'id')
        $displayName = [string](Get-ObjectValue -InputObject $group -Name 'displayName')
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $map.ContainsKey($id)) {
            $map[$id] = $displayName
        }
    }

    return $map
}

function Add-ResultToGrid {
    param(
        [Parameter(Mandatory = $true)]$GroupName,
        [Parameter(Mandatory = $true)]$Category,
        [Parameter(Mandatory = $true)]$Name,
        $Type = '',
        $Intent = '',
        $Platform = '',
        $Filter = '',
        $FilterMode = '',
        $ObjectId = '',
        $AssignmentId = '',
        $GroupId = '',
        $AssignmentType = '',
        $MatchKind = 'Direct',
        $Details = ''
    )

    Test-AnalysisCancellation

    $row = $script:ResultsTable.NewRow()
    $row['Group'] = ConvertTo-CellText -Value $GroupName
    $row['Category'] = ConvertTo-CellText -Value $Category
    $row['Name'] = ConvertTo-CellText -Value $Name
    $row['Type'] = ConvertTo-CellText -Value $Type
    $row['Intent'] = ConvertTo-CellText -Value $Intent
    $row['Platform'] = ConvertTo-CellText -Value $Platform
    $row['Filter'] = ConvertTo-CellText -Value $Filter
    $row['Filter mode'] = ConvertTo-CellText -Value $FilterMode
    $row['Object ID'] = ConvertTo-CellText -Value $ObjectId
    $row['Assignment ID'] = ConvertTo-CellText -Value $AssignmentId
    $row['Group ID'] = ConvertTo-CellText -Value $GroupId
    $row['Assignment type'] = ConvertTo-CellText -Value $AssignmentType
    $row['Match'] = ConvertTo-ScopeResultText -MatchKind (ConvertTo-CellText -Value $MatchKind) -AssignmentType (ConvertTo-CellText -Value $AssignmentType)
    $row['Details'] = ConvertTo-CellText -Value $Details
    [void]$script:ResultsTable.Rows.Add($row)
}

function Get-ConfigurationPolicyCategory {
    param($Policy)

    $templateReference = Get-ObjectValue -InputObject $Policy -Name 'templateReference'
    $endpointSecurityCategory = Get-EndpointSecurityCategory -Policy $Policy -DefaultCategory ''
    if (-not [string]::IsNullOrWhiteSpace($endpointSecurityCategory)) {
        return $endpointSecurityCategory
    }

    if ($null -eq $templateReference) {
        return 'Settings catalog'
    }

    $templateFamily = [string](Get-ObjectValue -InputObject $templateReference -Name 'templateFamily')
    $templateDisplayName = [string](Get-ObjectValue -InputObject $templateReference -Name 'templateDisplayName')
    $templateId = [string](Get-ObjectValue -InputObject $templateReference -Name 'templateId')
    $templateText = "$templateFamily $templateDisplayName $templateId"

    if ($templateText -match 'administrative|groupPolicy|admx') {
        return 'Administrative templates'
    }

    return 'Settings catalog'
}

function Get-EndpointSecurityCategory {
    param(
        $Policy,
        [string]$DefaultCategory = 'Endpoint security'
    )

    $templateReference = Get-ObjectValue -InputObject $Policy -Name 'templateReference'
    $parts = @(
        [string](Get-ObjectValue -InputObject $Policy -Name 'displayName'),
        [string](Get-ObjectValue -InputObject $Policy -Name 'name'),
        [string](Get-ObjectValue -InputObject $Policy -Name 'description'),
        [string](Get-ObjectValue -InputObject $Policy -Name '@odata.type'),
        [string](Get-ObjectValue -InputObject $Policy -Name 'templateId'),
        [string](Get-ObjectValue -InputObject $Policy -Name 'templateName'),
        [string](Get-ObjectValue -InputObject $Policy -Name 'templateDisplayName'),
        [string](Get-ObjectValue -InputObject $Policy -Name 'templateType')
    )

    if ($templateReference) {
        $parts += @(
            [string](Get-ObjectValue -InputObject $templateReference -Name 'templateFamily'),
            [string](Get-ObjectValue -InputObject $templateReference -Name 'templateDisplayName'),
            [string](Get-ObjectValue -InputObject $templateReference -Name 'templateId')
        )
    }

    $text = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '

    if ($text -match '(?i)firewall') {
        return 'Firewall rules'
    }

    if ($text -match '(?i)endpoint\s*security|endpointSecurity|security\s*baseline|baseline|antivirus|disk\s*encryption|attack\s*surface|account\s*protection|endpoint\s*detection|edr|application\s*control|app\s*control|applicationcontrol|wdac|windows\s+defender\s+application\s+control') {
        return 'Endpoint security'
    }

    return $DefaultCategory
}

function Get-PolicyDisplayName {
    param($Policy)

    foreach ($propertyName in @('displayName', 'name', 'title')) {
        $value = [string](Get-ObjectValue -InputObject $Policy -Name $propertyName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return [string](Get-ObjectValue -InputObject $Policy -Name 'id')
}

function Add-DeviceResultIfTargetMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups,
        [Parameter(Mandatory = $true)][string]$DeviceName,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        $Type = '',
        $Intent = '',
        $Platform = '',
        $ObjectId = '',
        $AssignmentId = '',
        $Details = ''
    )

    $targetDetails = Get-TargetDetails -Target $Target
    $assignmentType = [string]$targetDetails.AssignmentType
    $groupId = [string]$targetDetails.GroupId
    $isAllDevices = $assignmentType -match 'allDevicesAssignmentTarget'
    $isExclusion = $assignmentType -match 'exclusionGroupAssignmentTarget'

    $matchedGroupName = ''
    if (-not [string]::IsNullOrWhiteSpace($groupId) -and $DeviceGroups.ContainsKey($groupId)) {
        $matchedGroupName = [string]$DeviceGroups[$groupId]
        if ([string]::IsNullOrWhiteSpace($matchedGroupName)) {
            $matchedGroupName = $groupId
        }
    }

    if (-not $isAllDevices -and [string]::IsNullOrWhiteSpace($matchedGroupName)) {
        return
    }

    $matchKind = 'Via device group'
    $groupName = $matchedGroupName
    if ($isAllDevices) {
        $matchKind = 'All devices'
        $groupName = 'All devices'
    }
    elseif ($isExclusion) {
        $matchKind = 'Excluded by device group'
    }

    $deviceDetails = "Device: $DeviceName"
    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        $deviceDetails = "$deviceDetails | $Details"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$targetDetails.FilterId)) {
        $deviceDetails = "$deviceDetails | Intune filter present, evaluation not simulated"
    }

    Add-ResultToGrid `
        -GroupName $groupName `
        -Category $Category `
        -Name $Name `
        -Type $Type `
        -Intent $Intent `
        -Platform $Platform `
        -Filter $targetDetails.FilterId `
        -FilterMode $targetDetails.FilterMode `
        -ObjectId $ObjectId `
        -AssignmentId $AssignmentId `
        -GroupId $groupId `
        -AssignmentType $targetDetails.AssignmentType `
        -MatchKind $matchKind `
        -Details $deviceDetails
}

function Add-UserResultIfTargetMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Name,
        $Type = '',
        $Intent = '',
        $Platform = '',
        $ObjectId = '',
        $AssignmentId = '',
        $Details = ''
    )

    $targetDetails = Get-TargetDetails -Target $Target
    $assignmentType = [string]$targetDetails.AssignmentType
    $groupId = [string]$targetDetails.GroupId
    $isAllUsers = $assignmentType -match 'allUsersAssignmentTarget|allLicensedUsersAssignmentTarget'
    $isExclusion = $assignmentType -match 'exclusionGroupAssignmentTarget'

    $matchedGroupName = ''
    if (-not [string]::IsNullOrWhiteSpace($groupId) -and $UserGroups.ContainsKey($groupId)) {
        $matchedGroupName = [string]$UserGroups[$groupId]
        if ([string]::IsNullOrWhiteSpace($matchedGroupName)) {
            $matchedGroupName = $groupId
        }
    }

    if (-not $isAllUsers -and [string]::IsNullOrWhiteSpace($matchedGroupName)) {
        return
    }

    $matchKind = 'Via user group'
    $groupName = $matchedGroupName
    if ($isAllUsers) {
        $matchKind = 'All users'
        $groupName = 'All users'
    }
    elseif ($isExclusion) {
        $matchKind = 'Excluded by user group'
    }

    $userDetails = "User: $UserPrincipalName"
    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        $userDetails = "$userDetails | $Details"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$targetDetails.FilterId)) {
        $userDetails = "$userDetails | Intune filter present, evaluation not simulated"
    }

    Add-ResultToGrid `
        -GroupName $groupName `
        -Category $Category `
        -Name $Name `
        -Type $Type `
        -Intent $Intent `
        -Platform $Platform `
        -Filter $targetDetails.FilterId `
        -FilterMode $targetDetails.FilterMode `
        -ObjectId $ObjectId `
        -AssignmentId $AssignmentId `
        -GroupId $groupId `
        -AssignmentType $targetDetails.AssignmentType `
        -MatchKind $matchKind `
        -Details $userDetails
}

function Get-IntuneMobileAppAssignmentsByGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Group
    )

    Write-UiLog -Message "Reading Intune applications for $($Group.DisplayName)." -Level Info
    $apps = @(Invoke-GraphGetAllPages -Uri "/beta/deviceAppManagement/mobileApps?`$top=50")
    $index = 0

    foreach ($app in $apps) {
        Test-AnalysisCancellation
        $index++
        if (($index % 10) -eq 0) {
            Set-UiStatus -Text "Applications : $index / $($apps.Count)" -Percent 35
        }

        $appId = [string](Get-ObjectValue -InputObject $app -Name 'id')
        if ([string]::IsNullOrWhiteSpace($appId)) {
            continue
        }
        $appName = Get-PolicyDisplayName -Policy $app
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceAppManagement/mobileApps/$appId/assignments?`$top=50")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for application '$appName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            $target = Get-AssignmentTargetDetails -Assignment $assignment
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category 'Application' `
                    -Name $appName `
                    -Type ([string](Get-ObjectValue -InputObject $app -Name '@odata.type')) `
                    -Intent ([string](Get-ObjectValue -InputObject $assignment -Name 'intent')) `
                    -Platform '' `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId $appId `
                    -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId'
            }
        }
    }
}

function Get-IntuneMobileAppAssignmentsByDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups
    )

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Write-UiLog -Message "Reading Intune applications for device $deviceName." -Level Info
    $apps = @(Invoke-GraphGetAllPages -Uri "/beta/deviceAppManagement/mobileApps?`$top=50")
    $index = 0

    foreach ($app in $apps) {
        Test-AnalysisCancellation
        $index++
        if (($index % 10) -eq 0) {
            Set-UiStatus -Text "Device applications : $index / $($apps.Count)" -Percent 35
        }

        $appId = [string](Get-ObjectValue -InputObject $app -Name 'id')
        if ([string]::IsNullOrWhiteSpace($appId)) {
            continue
        }
        $appName = Get-PolicyDisplayName -Policy $app
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceAppManagement/mobileApps/$appId/assignments?`$top=50")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for application '$appName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            Add-DeviceResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category 'Application' `
                -Name $appName `
                -Type ([string](Get-ObjectValue -InputObject $app -Name '@odata.type')) `
                -Intent ([string](Get-ObjectValue -InputObject $assignment -Name 'intent')) `
                -Platform '' `
                -ObjectId $appId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id'))
        }
    }
}

function Get-IntuneMobileAppAssignmentsByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups
    )

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    Write-UiLog -Message "Reading Intune applications for user $userPrincipalName." -Level Info
    $apps = @(Invoke-GraphGetAllPages -Uri "/beta/deviceAppManagement/mobileApps?`$top=50")
    $index = 0

    foreach ($app in $apps) {
        Test-AnalysisCancellation
        $index++
        if (($index % 10) -eq 0) {
            Set-UiStatus -Text "User applications : $index / $($apps.Count)" -Percent 35
        }

        $appId = [string](Get-ObjectValue -InputObject $app -Name 'id')
        if ([string]::IsNullOrWhiteSpace($appId)) {
            continue
        }
        $appName = Get-PolicyDisplayName -Policy $app
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceAppManagement/mobileApps/$appId/assignments?`$top=50")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for application '$appName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            Add-UserResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category 'Application' `
                -Name $appName `
                -Type ([string](Get-ObjectValue -InputObject $app -Name '@odata.type')) `
                -Intent ([string](Get-ObjectValue -InputObject $assignment -Name 'intent')) `
                -Platform '' `
                -ObjectId $appId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id'))
        }
    }
}

function Get-IntuneConfigurationAssignmentsByGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Group
    )

    Write-UiLog -Message "Reading Intune configuration profiles for $($Group.DisplayName)." -Level Info

    $deviceConfigurations = @()
    try {
        $deviceConfigurations = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceConfigurations?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read device configurations : $($_.Exception.Message)" -Level Warn
    }

    foreach ($configuration in $deviceConfigurations) {
        Test-AnalysisCancellation
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceConfigurations/$($configuration.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for profile '$($configuration.DisplayName)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            $target = Get-TargetDetails -Target $assignment.Target
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category 'Configuration' `
                    -Name ([string]$configuration.DisplayName) `
                    -Type ([string](Get-ObjectValue -InputObject $configuration -Name '@odata.type')) `
                    -Intent '' `
                    -Platform ([string](Get-ObjectValue -InputObject $configuration -Name 'platforms')) `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId ([string]$configuration.Id) `
                    -AssignmentId ([string]$assignment.Id) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId'
            }
        }
    }

    $configurationPolicies = @()
    try {
        $configurationPolicies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/configurationPolicies?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read settings catalog policies : $($_.Exception.Message)" -Level Warn
    }

    foreach ($policy in $configurationPolicies) {
        Test-AnalysisCancellation
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/configurationPolicies/$($policy.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for configuration '$($policy.Name)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            $target = Get-TargetDetails -Target $assignment.Target
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category (Get-ConfigurationPolicyCategory -Policy $policy) `
                    -Name ([string]$policy.Name) `
                    -Type ([string](Get-ObjectValue -InputObject $policy -Name 'templateReference')) `
                    -Intent '' `
                    -Platform ([string]$policy.Platforms) `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId ([string]$policy.Id) `
                    -AssignmentId ([string]$assignment.Id) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId' `
                    -Details 'Configuration policy'
            }
        }
    }

    $administrativeTemplates = @()
    try {
        $administrativeTemplates = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/groupPolicyConfigurations?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read administrative templates : $($_.Exception.Message)" -Level Warn
    }

    foreach ($template in $administrativeTemplates) {
        Test-AnalysisCancellation
        $templateId = [string](Get-ObjectValue -InputObject $template -Name 'id')
        $templateName = [string](Get-ObjectValue -InputObject $template -Name 'displayName')
        if ([string]::IsNullOrWhiteSpace($templateId)) {
            continue
        }

        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/groupPolicyConfigurations/$templateId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for administrative template '$templateName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            $target = Get-AssignmentTargetDetails -Assignment $assignment
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category 'Administrative templates' `
                    -Name $templateName `
                    -Type ([string](Get-ObjectValue -InputObject $template -Name '@odata.type')) `
                    -Intent '' `
                    -Platform '' `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId $templateId `
                    -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId'
            }
        }
    }
}

function Get-IntuneConfigurationAssignmentsByDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups
    )

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Write-UiLog -Message "Reading Intune configuration profiles for device $deviceName." -Level Info

    $deviceConfigurations = @()
    try {
        $deviceConfigurations = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceConfigurations?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read device configurations : $($_.Exception.Message)" -Level Warn
    }

    foreach ($configuration in $deviceConfigurations) {
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceConfigurations/$($configuration.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for profile '$($configuration.DisplayName)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-DeviceResultIfTargetMatches `
                -Target $assignment.Target `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category 'Configuration' `
                -Name ([string]$configuration.DisplayName) `
                -Type ([string](Get-ObjectValue -InputObject $configuration -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $configuration -Name 'platforms')) `
                -ObjectId ([string]$configuration.Id) `
                -AssignmentId ([string]$assignment.Id)
        }
    }

    $configurationPolicies = @()
    try {
        $configurationPolicies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/configurationPolicies?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read settings catalog policies : $($_.Exception.Message)" -Level Warn
    }

    foreach ($policy in $configurationPolicies) {
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/configurationPolicies/$($policy.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for configuration '$($policy.Name)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-DeviceResultIfTargetMatches `
                -Target $assignment.Target `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category (Get-ConfigurationPolicyCategory -Policy $policy) `
                -Name ([string]$policy.Name) `
                -Type ([string](Get-ObjectValue -InputObject $policy -Name 'templateReference')) `
                -Intent '' `
                -Platform ([string]$policy.Platforms) `
                -ObjectId ([string]$policy.Id) `
                -AssignmentId ([string]$assignment.Id) `
                -Details 'Configuration policy'
        }
    }

    $administrativeTemplates = @()
    try {
        $administrativeTemplates = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/groupPolicyConfigurations?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read administrative templates : $($_.Exception.Message)" -Level Warn
    }

    foreach ($template in $administrativeTemplates) {
        Test-AnalysisCancellation
        $templateId = [string](Get-ObjectValue -InputObject $template -Name 'id')
        $templateName = [string](Get-ObjectValue -InputObject $template -Name 'displayName')
        if ([string]::IsNullOrWhiteSpace($templateId)) {
            continue
        }

        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/groupPolicyConfigurations/$templateId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for administrative template '$templateName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            Add-DeviceResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category 'Administrative templates' `
                -Name $templateName `
                -Type ([string](Get-ObjectValue -InputObject $template -Name '@odata.type')) `
                -Intent '' `
                -Platform '' `
                -ObjectId $templateId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id'))
        }
    }
}

function Get-IntuneConfigurationAssignmentsByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups
    )

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    Write-UiLog -Message "Reading Intune configuration profiles for user $userPrincipalName." -Level Info

    $deviceConfigurations = @()
    try {
        $deviceConfigurations = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceConfigurations?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read device configurations : $($_.Exception.Message)" -Level Warn
    }

    foreach ($configuration in $deviceConfigurations) {
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceConfigurations/$($configuration.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for profile '$($configuration.DisplayName)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-UserResultIfTargetMatches `
                -Target $assignment.Target `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category 'Configuration' `
                -Name ([string]$configuration.DisplayName) `
                -Type ([string](Get-ObjectValue -InputObject $configuration -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $configuration -Name 'platforms')) `
                -ObjectId ([string]$configuration.Id) `
                -AssignmentId ([string]$assignment.Id)
        }
    }

    $configurationPolicies = @()
    try {
        $configurationPolicies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/configurationPolicies?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read settings catalog policies : $($_.Exception.Message)" -Level Warn
    }

    foreach ($policy in $configurationPolicies) {
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/configurationPolicies/$($policy.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for configuration '$($policy.Name)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-UserResultIfTargetMatches `
                -Target $assignment.Target `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category (Get-ConfigurationPolicyCategory -Policy $policy) `
                -Name ([string]$policy.Name) `
                -Type ([string](Get-ObjectValue -InputObject $policy -Name 'templateReference')) `
                -Intent '' `
                -Platform ([string]$policy.Platforms) `
                -ObjectId ([string]$policy.Id) `
                -AssignmentId ([string]$assignment.Id) `
                -Details 'Configuration policy'
        }
    }

    $administrativeTemplates = @()
    try {
        $administrativeTemplates = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/groupPolicyConfigurations?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read administrative templates : $($_.Exception.Message)" -Level Warn
    }

    foreach ($template in $administrativeTemplates) {
        $templateId = [string](Get-ObjectValue -InputObject $template -Name 'id')
        $templateName = [string](Get-ObjectValue -InputObject $template -Name 'displayName')
        if ([string]::IsNullOrWhiteSpace($templateId)) {
            continue
        }

        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/groupPolicyConfigurations/$templateId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for administrative template '$templateName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-UserResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category 'Administrative templates' `
                -Name $templateName `
                -Type ([string](Get-ObjectValue -InputObject $template -Name '@odata.type')) `
                -Intent '' `
                -Platform '' `
                -ObjectId $templateId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id'))
        }
    }
}

function Get-IntuneEndpointSecurityAssignmentsByGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Group
    )

    Write-UiLog -Message "Reading Endpoint security policies for $($Group.DisplayName)." -Level Info

    $policies = @()
    try {
        $policies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/intents?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read Endpoint security intents : $($_.Exception.Message)" -Level Warn
    }

    foreach ($policy in $policies) {
        $policyId = [string](Get-ObjectValue -InputObject $policy -Name 'id')
        if ([string]::IsNullOrWhiteSpace($policyId)) {
            continue
        }

        $policyName = Get-PolicyDisplayName -Policy $policy
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/intents/$policyId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read Endpoint security assignments '$policyName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            $target = Get-AssignmentTargetDetails -Assignment $assignment
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category (Get-EndpointSecurityCategory -Policy $policy) `
                    -Name $policyName `
                    -Type ([string](Get-ObjectValue -InputObject $policy -Name '@odata.type')) `
                    -Intent '' `
                    -Platform '' `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId $policyId `
                    -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId' `
                    -Details 'Endpoint security intent'
            }
        }
    }
}

function Get-IntuneEndpointSecurityAssignmentsByDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups
    )

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Write-UiLog -Message "Reading Endpoint security policies for device $deviceName." -Level Info

    $policies = @()
    try {
        $policies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/intents?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read Endpoint security intents : $($_.Exception.Message)" -Level Warn
    }

    foreach ($policy in $policies) {
        $policyId = [string](Get-ObjectValue -InputObject $policy -Name 'id')
        if ([string]::IsNullOrWhiteSpace($policyId)) {
            continue
        }

        $policyName = Get-PolicyDisplayName -Policy $policy
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/intents/$policyId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read Endpoint security assignments '$policyName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-DeviceResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category (Get-EndpointSecurityCategory -Policy $policy) `
                -Name $policyName `
                -Type ([string](Get-ObjectValue -InputObject $policy -Name '@odata.type')) `
                -Intent '' `
                -Platform '' `
                -ObjectId $policyId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                -Details 'Endpoint security intent'
        }
    }
}

function Get-IntuneEndpointSecurityAssignmentsByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups
    )

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    Write-UiLog -Message "Reading Endpoint security policies for user $userPrincipalName." -Level Info

    $policies = @()
    try {
        $policies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/intents?`$top=999")
    }
    catch {
        Write-UiLog -Message "Unable to read Endpoint security intents : $($_.Exception.Message)" -Level Warn
    }

    foreach ($policy in $policies) {
        $policyId = [string](Get-ObjectValue -InputObject $policy -Name 'id')
        if ([string]::IsNullOrWhiteSpace($policyId)) {
            continue
        }

        $policyName = Get-PolicyDisplayName -Policy $policy
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/intents/$policyId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read Endpoint security assignments '$policyName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-UserResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category (Get-EndpointSecurityCategory -Policy $policy) `
                -Name $policyName `
                -Type ([string](Get-ObjectValue -InputObject $policy -Name '@odata.type')) `
                -Intent '' `
                -Platform '' `
                -ObjectId $policyId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                -Details 'Endpoint security intent'
        }
    }
}

function Get-IntuneComplianceAssignmentsByGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Group
    )

    Write-UiLog -Message "Reading Intune compliance policies for $($Group.DisplayName)." -Level Info
    $policies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceCompliancePolicies?`$top=999")

    foreach ($policy in $policies) {
        Test-AnalysisCancellation
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceCompliancePolicies/$($policy.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for policy '$($policy.DisplayName)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            $target = Get-TargetDetails -Target $assignment.Target
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category 'Compliance policy' `
                    -Name ([string]$policy.DisplayName) `
                    -Type ([string](Get-ObjectValue -InputObject $policy -Name '@odata.type')) `
                    -Intent '' `
                    -Platform ([string](Get-ObjectValue -InputObject $policy -Name 'platforms')) `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId ([string]$policy.Id) `
                    -AssignmentId ([string]$assignment.Id) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId'
            }
        }
    }
}

function Get-IntuneComplianceAssignmentsByDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups
    )

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Write-UiLog -Message "Reading Intune compliance policies for device $deviceName." -Level Info
    $policies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceCompliancePolicies?`$top=999")

    foreach ($policy in $policies) {
        Test-AnalysisCancellation
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceCompliancePolicies/$($policy.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for policy '$($policy.DisplayName)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            Add-DeviceResultIfTargetMatches `
                -Target $assignment.Target `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category 'Compliance policy' `
                -Name ([string]$policy.DisplayName) `
                -Type ([string](Get-ObjectValue -InputObject $policy -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $policy -Name 'platforms')) `
                -ObjectId ([string]$policy.Id) `
                -AssignmentId ([string]$assignment.Id)
        }
    }
}

function Get-IntuneComplianceAssignmentsByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups
    )

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    Write-UiLog -Message "Reading Intune compliance policies for user $userPrincipalName." -Level Info
    $policies = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceCompliancePolicies?`$top=999")

    foreach ($policy in $policies) {
        Test-AnalysisCancellation
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceCompliancePolicies/$($policy.Id)/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read assignments for policy '$($policy.DisplayName)' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            Add-UserResultIfTargetMatches `
                -Target $assignment.Target `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category 'Compliance policy' `
                -Name ([string]$policy.DisplayName) `
                -Type ([string](Get-ObjectValue -InputObject $policy -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $policy -Name 'platforms')) `
                -ObjectId ([string]$policy.Id) `
                -AssignmentId ([string]$assignment.Id)
        }
    }
}

function Get-IntuneRemediationAssignmentsByGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Group
    )

    Write-UiLog -Message "Reading Intune remediations for $($Group.DisplayName)." -Level Info

    $scripts = @()
    try {
        $scripts = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceHealthScripts?`$top=999")
    }
    catch {
        Write-UiLog -Message "Remediations skipped, access was not granted or Graph returned an error : $($_.Exception.Message)" -Level Warn
    }

    foreach ($scriptObject in $scripts) {
        $scriptId = [string](Get-ObjectValue -InputObject $scriptObject -Name 'id')
        if ([string]::IsNullOrWhiteSpace($scriptId)) {
            continue
        }

        $scriptName = Get-PolicyDisplayName -Policy $scriptObject
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read remediation assignments '$scriptName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            $target = Get-AssignmentTargetDetails -Assignment $assignment
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category 'Remediation' `
                    -Name $scriptName `
                    -Type ([string](Get-ObjectValue -InputObject $scriptObject -Name '@odata.type')) `
                    -Intent '' `
                    -Platform ([string](Get-ObjectValue -InputObject $scriptObject -Name 'runAsAccount')) `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId $scriptId `
                    -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId' `
                    -Details 'Device health script'
            }
        }
    }
}

function Get-IntuneRemediationAssignmentsByDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups
    )

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Write-UiLog -Message "Reading Intune remediations for device $deviceName." -Level Info

    $scripts = @()
    try {
        $scripts = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceHealthScripts?`$top=999")
    }
    catch {
        Write-UiLog -Message "Remediations skipped, access was not granted or Graph returned an error : $($_.Exception.Message)" -Level Warn
    }

    foreach ($scriptObject in $scripts) {
        $scriptId = [string](Get-ObjectValue -InputObject $scriptObject -Name 'id')
        if ([string]::IsNullOrWhiteSpace($scriptId)) {
            continue
        }

        $scriptName = Get-PolicyDisplayName -Policy $scriptObject
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read remediation assignments '$scriptName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-DeviceResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category 'Remediation' `
                -Name $scriptName `
                -Type ([string](Get-ObjectValue -InputObject $scriptObject -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $scriptObject -Name 'runAsAccount')) `
                -ObjectId $scriptId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                -Details 'Device health script'
        }
    }
}

function Get-IntuneRemediationAssignmentsByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups
    )

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    Write-UiLog -Message "Reading Intune remediations for user $userPrincipalName." -Level Info

    $scripts = @()
    try {
        $scripts = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceHealthScripts?`$top=999")
    }
    catch {
        Write-UiLog -Message "Remediations skipped, access was not granted or Graph returned an error : $($_.Exception.Message)" -Level Warn
    }

    foreach ($scriptObject in $scripts) {
        $scriptId = [string](Get-ObjectValue -InputObject $scriptObject -Name 'id')
        if ([string]::IsNullOrWhiteSpace($scriptId)) {
            continue
        }

        $scriptName = Get-PolicyDisplayName -Policy $scriptObject
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read remediation assignments '$scriptName' : $($_.Exception.Message)" -Level Warn
            continue
        }

        foreach ($assignment in $assignments) {
            Add-UserResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category 'Remediation' `
                -Name $scriptName `
                -Type ([string](Get-ObjectValue -InputObject $scriptObject -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $scriptObject -Name 'runAsAccount')) `
                -ObjectId $scriptId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                -Details 'Device health script'
        }
    }
}

function Get-IntunePowerShellScriptAssignmentsByGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Group
    )

    Write-UiLog -Message "Reading Intune PowerShell scripts for $($Group.DisplayName)." -Level Info

    $scripts = @()
    try {
        $scripts = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts?`$top=999")
    }
    catch {
        Write-UiLog -Message "PowerShell scripts skipped, access was not granted or Graph returned an error : $($_.Exception.Message)" -Level Warn
    }

    foreach ($scriptObject in $scripts) {
        $scriptId = [string](Get-ObjectValue -InputObject $scriptObject -Name 'id')
        if ([string]::IsNullOrWhiteSpace($scriptId)) {
            continue
        }

        $scriptName = Get-PolicyDisplayName -Policy $scriptObject
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read PowerShell script assignments '$scriptName' : $($_.Exception.Message)" -Level Warn
            $assignments = @()
        }

        try {
            $groupAssignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/groupAssignments?`$top=999")
            $assignments += @($groupAssignments)
        }
        catch {
            Write-UiLog -Message "Unable to read PowerShell script group assignments '$scriptName' : $($_.Exception.Message)" -Level Verbose
        }

        foreach ($assignment in $assignments) {
            Test-AnalysisCancellation
            $target = Get-AssignmentTargetDetails -Assignment $assignment
            if ($target.GroupId -and $target.GroupId -eq $Group.Id) {
                Add-ResultToGrid `
                    -GroupName $Group.DisplayName `
                    -Category 'PowerShell script' `
                    -Name $scriptName `
                    -Type ([string](Get-ObjectValue -InputObject $scriptObject -Name '@odata.type')) `
                    -Intent '' `
                    -Platform ([string](Get-ObjectValue -InputObject $scriptObject -Name 'runAsAccount')) `
                    -Filter $target.FilterId `
                    -FilterMode $target.FilterMode `
                    -ObjectId $scriptId `
                    -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                    -GroupId ([string]$Group.Id) `
                    -AssignmentType $target.AssignmentType `
                    -MatchKind 'Direct by groupId' `
                    -Details 'Device management script'
            }
        }
    }
}

function Get-IntunePowerShellScriptAssignmentsByDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [Parameter(Mandatory = $true)][hashtable]$DeviceGroups
    )

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Write-UiLog -Message "Reading Intune PowerShell scripts for device $deviceName." -Level Info

    $scripts = @()
    try {
        $scripts = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts?`$top=999")
    }
    catch {
        Write-UiLog -Message "PowerShell scripts skipped, access was not granted or Graph returned an error : $($_.Exception.Message)" -Level Warn
    }

    foreach ($scriptObject in $scripts) {
        $scriptId = [string](Get-ObjectValue -InputObject $scriptObject -Name 'id')
        if ([string]::IsNullOrWhiteSpace($scriptId)) {
            continue
        }

        $scriptName = Get-PolicyDisplayName -Policy $scriptObject
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read PowerShell script assignments '$scriptName' : $($_.Exception.Message)" -Level Warn
            $assignments = @()
        }

        try {
            $groupAssignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/groupAssignments?`$top=999")
            $assignments += @($groupAssignments)
        }
        catch {
            Write-UiLog -Message "Unable to read PowerShell script group assignments '$scriptName' : $($_.Exception.Message)" -Level Verbose
        }

        foreach ($assignment in $assignments) {
            Add-DeviceResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -DeviceGroups $DeviceGroups `
                -DeviceName $deviceName `
                -Category 'PowerShell script' `
                -Name $scriptName `
                -Type ([string](Get-ObjectValue -InputObject $scriptObject -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $scriptObject -Name 'runAsAccount')) `
                -ObjectId $scriptId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                -Details 'Device management script'
        }
    }
}

function Get-IntunePowerShellScriptAssignmentsByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [Parameter(Mandatory = $true)][hashtable]$UserGroups
    )

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    Write-UiLog -Message "Reading Intune PowerShell scripts for user $userPrincipalName." -Level Info

    $scripts = @()
    try {
        $scripts = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts?`$top=999")
    }
    catch {
        Write-UiLog -Message "PowerShell scripts skipped, access was not granted or Graph returned an error : $($_.Exception.Message)" -Level Warn
    }

    foreach ($scriptObject in $scripts) {
        $scriptId = [string](Get-ObjectValue -InputObject $scriptObject -Name 'id')
        if ([string]::IsNullOrWhiteSpace($scriptId)) {
            continue
        }

        $scriptName = Get-PolicyDisplayName -Policy $scriptObject
        try {
            $assignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/assignments?`$top=999")
        }
        catch {
            Write-UiLog -Message "Unable to read PowerShell script assignments '$scriptName' : $($_.Exception.Message)" -Level Warn
            $assignments = @()
        }

        try {
            $groupAssignments = @(Invoke-GraphGetAllPages -Uri "/beta/deviceManagement/deviceManagementScripts/$scriptId/groupAssignments?`$top=999")
            $assignments += @($groupAssignments)
        }
        catch {
            Write-UiLog -Message "Unable to read PowerShell script group assignments '$scriptName' : $($_.Exception.Message)" -Level Verbose
        }

        foreach ($assignment in $assignments) {
            Add-UserResultIfTargetMatches `
                -Target (Get-AssignmentTargetObject -Assignment $assignment) `
                -UserGroups $UserGroups `
                -UserPrincipalName $userPrincipalName `
                -Category 'PowerShell script' `
                -Name $scriptName `
                -Type ([string](Get-ObjectValue -InputObject $scriptObject -Name '@odata.type')) `
                -Intent '' `
                -Platform ([string](Get-ObjectValue -InputObject $scriptObject -Name 'runAsAccount')) `
                -ObjectId $scriptId `
                -AssignmentId ([string](Get-ObjectValue -InputObject $assignment -Name 'id')) `
                -Details 'Device management script'
        }
    }
}

function Update-Counts {
    $total = $script:ResultsTable.Rows.Count
    $apps = ($script:ResultsTable.Select("Category = 'Application'")).Count
    $configs = ($script:ResultsTable.Select("Category = 'Configuration'")).Count
    $compliance = ($script:ResultsTable.Select("Category = 'Compliance policy'")).Count
    $settingsCatalog = ($script:ResultsTable.Select("Category = 'Settings catalog'")).Count
    $administrativeTemplates = ($script:ResultsTable.Select("Category = 'Administrative templates'")).Count
    $endpointSecurity = ($script:ResultsTable.Select("Category = 'Endpoint security'")).Count
    $firewallRules = ($script:ResultsTable.Select("Category = 'Firewall rules'")).Count
    $remediations = ($script:ResultsTable.Select("Category = 'Remediation'")).Count
    $powerShellScripts = ($script:ResultsTable.Select("Category = 'PowerShell script'")).Count

    $metrics = [ordered]@{
        Total = $total
        Apps = $apps
        Config = $configs
        Compliance = $compliance
        Settings = $settingsCatalog
        'Admin templates' = $administrativeTemplates
        Endpoint = $endpointSecurity
        Firewall = $firewallRules
        Remediations = $remediations
        Scripts = $powerShellScripts
    }

    foreach ($name in $metrics.Keys) {
        if ($script:metricValueLabels -and $script:metricValueLabels.ContainsKey($name)) {
            $script:metricValueLabels[$name].Text = [string]$metrics[$name]
        }
    }

}

function Set-ComboBoxItems {
    param(
        [Parameter(Mandatory = $true)]$ComboBox,
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Items = @(),
        [string]$DefaultItem = 'Tous'
    )

    $current = [string]$ComboBox.SelectedItem
    $ComboBox.BeginUpdate()
    $ComboBox.Items.Clear()
    [void]$ComboBox.Items.Add($DefaultItem)
    foreach ($item in $Items) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            [void]$ComboBox.Items.Add($item)
        }
    }

    $index = $ComboBox.Items.IndexOf($current)
    if ($index -lt 0) { $index = 0 }
    $ComboBox.SelectedIndex = $index
    $ComboBox.EndUpdate()
}

function Set-CheckedComboBoxItems {
    param(
        [Parameter(Mandatory = $true)]$ComboBox,
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Items = @()
    )

    $cleanItems = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $stringItems = New-Object 'System.String[]' $cleanItems.Count
    for ($index = 0; $index -lt $cleanItems.Count; $index++) {
        $stringItems[$index] = [string]$cleanItems[$index]
    }

    $ComboBox.SetItems($stringItems)
}

function Update-FilterChoices {
    if (-not $script:ResultsTable) { return }

    if ($script:cboGroupFilter) {
        $groups = @(
            $script:ResultsTable.Rows |
                ForEach-Object { [string]$_['Group'] } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        Set-CheckedComboBoxItems -ComboBox $script:cboGroupFilter -Items $groups
    }

    if ($script:cboIntentFilter) {
        $intents = @(
            $script:ResultsTable.Rows |
                ForEach-Object { [string]$_['Intent'] } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        Set-CheckedComboBoxItems -ComboBox $script:cboIntentFilter -Items $intents
    }

    if ($script:cboScopeFilter) {
        Set-CheckedComboBoxItems -ComboBox $script:cboScopeFilter -Items ([string[]]@('Include', 'Exclude'))
    }
}

function ConvertTo-RowFilterText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return $Text.Replace("'", "''").Replace("[", "[[]").Replace("%", "[%]").Replace("*", "[*]")
}

function Get-CheckedFilterValues {
    param($ComboBox)

    if (-not $ComboBox) { return @() }
    return @($ComboBox.GetCheckedItems() | ForEach-Object { [string]$_ })
}

function New-InRowFilter {
    param(
        [Parameter(Mandatory = $true)][string]$ColumnName,
        [Parameter(Mandatory = $true)][string[]]$Values
    )

    if ($Values.Count -eq 0) {
        return '1 = 0'
    }

    $parts = foreach ($value in $Values) {
        $safe = ConvertTo-RowFilterText -Text $value
        "$ColumnName = '$safe'"
    }

    return '(' + ($parts -join ' OR ') + ')'
}

function New-ScopeRowFilter {
    param(
        [Parameter(Mandatory = $true)][string[]]$Values
    )

    if ($Values.Count -eq 0) {
        return '1 = 0'
    }

    $parts = foreach ($value in $Values) {
        switch ($value) {
            'Include' { "[Match] LIKE 'Included%'" }
            'Exclude' { "[Match] LIKE 'Excluded%'" }
        }
    }

    $parts = @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0) { return '1 = 0' }

    return '(' + ($parts -join ' OR ') + ')'
}

function Apply-LocalFilter {
    $filter = ConvertTo-RowFilterText -Text $script:txtResultFilter.Text.Trim()
    $groupValues = @(Get-CheckedFilterValues -ComboBox $script:cboGroupFilter)
    $groupTotal = if ($script:cboGroupFilter) { $script:cboGroupFilter.GetItemCount() } else { 0 }

    $categoryValues = @(Get-CheckedFilterValues -ComboBox $script:cboCategoryFilter)
    $categoryTotal = if ($script:cboCategoryFilter) { $script:cboCategoryFilter.GetItemCount() } else { 0 }

    $intentValues = @(Get-CheckedFilterValues -ComboBox $script:cboIntentFilter)
    $intentTotal = if ($script:cboIntentFilter) { $script:cboIntentFilter.GetItemCount() } else { 0 }

    $scopeValues = @(Get-CheckedFilterValues -ComboBox $script:cboScopeFilter)
    $scopeTotal = if ($script:cboScopeFilter) { $script:cboScopeFilter.GetItemCount() } else { 0 }

    $filterParts = @()
    if ($groupTotal -gt 0 -and $groupValues.Count -lt $groupTotal) {
        $filterParts += New-InRowFilter -ColumnName 'Group' -Values $groupValues
    }

    if ($categoryTotal -gt 0 -and $categoryValues.Count -lt $categoryTotal) {
        $filterParts += New-InRowFilter -ColumnName 'Category' -Values $categoryValues
    }

    if ($intentTotal -gt 0 -and $intentValues.Count -lt $intentTotal) {
        $filterParts += New-InRowFilter -ColumnName 'Intent' -Values $intentValues
    }

    if ($scopeTotal -gt 0 -and $scopeValues.Count -lt $scopeTotal) {
        $filterParts += New-ScopeRowFilter -Values $scopeValues
    }

    if (-not [string]::IsNullOrWhiteSpace($filter)) {
        $columns = @('Group', 'Category', 'Name', 'Type', 'Intent', 'Platform', 'Filter', 'Filter mode', 'Object ID', 'Assignment ID', 'Group ID', 'Assignment type', 'Details')
        $textParts = foreach ($column in $columns) {
            "CONVERT([$column], 'System.String') LIKE '%$filter%'"
        }
        $filterParts += '(' + ($textParts -join ' OR ') + ')'
    }

    if ($filterParts.Count -eq 0) {
        $script:BindingSource.RemoveFilter()
        return
    }

    $script:BindingSource.Filter = ($filterParts -join ' AND ')
}

function Get-CategoryPalette {
    param([string]$Category)

    switch ($Category) {
        'Total' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(31, 35, 40)
                Accent = [System.Drawing.Color]::FromArgb(124, 200, 255)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Application' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(24, 49, 67)
                Accent = [System.Drawing.Color]::FromArgb(38, 117, 168)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Configuration' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(26, 54, 43)
                Accent = [System.Drawing.Color]::FromArgb(45, 132, 93)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Compliance policy' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(67, 46, 26)
                Accent = [System.Drawing.Color]::FromArgb(184, 111, 48)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Settings catalog' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(45, 40, 67)
                Accent = [System.Drawing.Color]::FromArgb(116, 90, 176)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Administrative templates' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(64, 36, 57)
                Accent = [System.Drawing.Color]::FromArgb(169, 82, 151)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Endpoint security' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(52, 43, 31)
                Accent = [System.Drawing.Color]::FromArgb(149, 117, 68)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Firewall rules' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(65, 35, 35)
                Accent = [System.Drawing.Color]::FromArgb(166, 77, 77)
                Fore = [System.Drawing.Color]::White
            }
        }
        'Remediation' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(35, 56, 58)
                Accent = [System.Drawing.Color]::FromArgb(64, 146, 153)
                Fore = [System.Drawing.Color]::White
            }
        }
        'PowerShell script' {
            return @{
                Back = [System.Drawing.Color]::FromArgb(50, 48, 37)
                Accent = [System.Drawing.Color]::FromArgb(154, 138, 73)
                Fore = [System.Drawing.Color]::White
            }
        }
        default {
            return @{
                Back = [System.Drawing.Color]::FromArgb(31, 35, 40)
                Accent = [System.Drawing.Color]::FromArgb(82, 91, 103)
                Fore = [System.Drawing.Color]::White
            }
        }
    }
}

function Apply-CategoryRowStyle {
    param(
        [Parameter(Mandatory = $true)]$Grid,
        [Parameter(Mandatory = $true)]$EventArgs
    )

    if ($EventArgs.RowIndex -lt 0) { return }
    if ($EventArgs.ColumnIndex -lt 0) { return }

    $row = $Grid.Rows[$EventArgs.RowIndex]
    if (-not $row -or -not $Grid.Columns.Contains('Category')) { return }

    $category = [string]$row.Cells['Category'].Value
    if ([string]::IsNullOrWhiteSpace($category)) { return }

    $palette = Get-CategoryPalette -Category $category
    $row.DefaultCellStyle.BackColor = $palette.Back
    $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(232, 236, 241)
    $row.DefaultCellStyle.SelectionBackColor = $palette.Accent
    $row.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

    if ($Grid.Columns[$EventArgs.ColumnIndex].Name -eq 'Category') {
        $EventArgs.CellStyle.BackColor = $palette.Accent
        $EventArgs.CellStyle.ForeColor = $palette.Fore
        $EventArgs.CellStyle.SelectionBackColor = $palette.Accent
        $EventArgs.CellStyle.SelectionForeColor = $palette.Fore
        $EventArgs.CellStyle.Font = New-Object System.Drawing.Font($Grid.Font, [System.Drawing.FontStyle]::Bold)
    }
}

function New-MetricCard {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][hashtable]$Theme
    )

    $palette = Get-CategoryPalette -Category $Category

    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(108, 58)
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 8)
    $card.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
    $card.BackColor = $palette.Back
    $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $card.Tag = 'MetricCard'
    $card.Cursor = [System.Windows.Forms.Cursors]::Hand

    $clickFilter = {
        Invoke-MetricCategoryFilter -Category $Category
    }.GetNewClosure()
    $card.Add_Click($clickFilter)

    $accent = New-Object System.Windows.Forms.Panel
    $accent.Dock = 'Left'
    $accent.Width = 3
    $accent.BackColor = $palette.Accent
    $accent.Tag = 'MetricAccent'
    $accent.Cursor = [System.Windows.Forms.Cursors]::Hand
    $accent.Add_Click($clickFilter)
    $card.Controls.Add($accent)

    $title = New-Object System.Windows.Forms.Label
    $title.Name = 'MetricTitle'
    $title.Text = $Name
    $title.Location = New-Object System.Drawing.Point(12, 6)
    $title.Size = New-Object System.Drawing.Size(88, 18)
    $title.ForeColor = $Theme.MutedText
    $title.BackColor = [System.Drawing.Color]::Transparent
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Regular)
    $title.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $title.AutoEllipsis = $true
    $title.Cursor = [System.Windows.Forms.Cursors]::Hand
    $title.Add_Click($clickFilter)
    $card.Controls.Add($title)

    $value = New-Object System.Windows.Forms.Label
    $value.Name = 'MetricValue'
    $value.Text = '0'
    $value.Location = New-Object System.Drawing.Point(12, 24)
    $value.Size = New-Object System.Drawing.Size(88, 26)
    $value.ForeColor = [System.Drawing.Color]::White
    $value.BackColor = [System.Drawing.Color]::Transparent
    $value.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $value.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $value.AutoEllipsis = $true
    $value.Cursor = [System.Windows.Forms.Cursors]::Hand
    $value.Add_Click($clickFilter)
    $card.Controls.Add($value)

    [void]$Parent.Controls.Add($card)
    $script:metricValueLabels[$Name] = $value
}

function Invoke-MetricCategoryFilter {
    param(
        [Parameter(Mandatory = $true)][string]$Category
    )

    if (-not $script:cboCategoryFilter) { return }

    if ($Category -eq 'Total') {
        $script:cboCategoryFilter.SetCheckedItems([string[]]@())
    }
    else {
        $script:cboCategoryFilter.SetCheckedItems([string[]]@($Category))
    }

    Apply-LocalFilter
}

function Set-AnalysisButtonsEnabled {
    param([bool]$Enabled)

    foreach ($button in @($script:AnalysisButtons)) {
        if ($button) {
            $button.Enabled = $Enabled
        }
    }
}

function Update-MetricCardLayout {
    if (-not $script:metricsPanel) { return }

    $cards = @(
        $script:metricsPanel.Controls |
            Where-Object { $_.Tag -and [string]$_.Tag -eq 'MetricCard' }
    )
    if ($cards.Count -eq 0) { return }

    $gap = 6
    $availableWidth = [Math]::Max(1, $script:metricsPanel.ClientSize.Width)
    $cardWidth = [Math]::Floor(($availableWidth - (($cards.Count - 1) * $gap)) / $cards.Count)
    $cardWidth = [Math]::Max(86, [Math]::Min(122, $cardWidth))
    $labelWidth = [Math]::Max(64, $cardWidth - 20)

    foreach ($card in $cards) {
        $card.Width = $cardWidth
        foreach ($child in $card.Controls) {
            if ($child.Name -eq 'MetricTitle' -or $child.Name -eq 'MetricValue') {
                $child.Width = $labelWidth
            }
        }
    }
}

function Get-MetricCardsContentWidth {
    if (-not $script:metricsPanel) {
        return 0
    }

    $cards = @(
        $script:metricsPanel.Controls |
            Where-Object { $_.Tag -and [string]$_.Tag -eq 'MetricCard' }
    )
    if ($cards.Count -eq 0) {
        return 0
    }

    $gap = 6
    $availableWidth = [Math]::Max(1, $script:metricsPanel.ClientSize.Width)
    $cardWidth = [Math]::Floor(($availableWidth - (($cards.Count - 1) * $gap)) / $cards.Count)
    $cardWidth = [Math]::Max(86, [Math]::Min(122, $cardWidth))
    return (($cards.Count * $cardWidth) + (($cards.Count - 1) * $gap))
}

function Invoke-HeaderLayout {
    if ($script:UpdateHeaderLayout -is [scriptblock]) {
        & $script:UpdateHeaderLayout
    }
}

function Apply-AssignmentMatchCellStyle {
    param(
        [Parameter(Mandatory = $true)]$Grid,
        [Parameter(Mandatory = $true)]$EventArgs
    )

    if ($EventArgs.RowIndex -lt 0) { return }
    if ($EventArgs.ColumnIndex -lt 0) { return }
    if ($Grid.Columns[$EventArgs.ColumnIndex].Name -ne 'Match') { return }

    $row = $Grid.Rows[$EventArgs.RowIndex]
    if (-not $row) { return }

    $matchKind = [string]$row.Cells['Match'].Value
    if ([string]::IsNullOrWhiteSpace($matchKind)) { return }

    $assignmentType = ''
    if ($Grid.Columns.Contains('Assignment type')) {
        $assignmentType = [string]$row.Cells['Assignment type'].Value
    }

    $isExclusion = ($matchKind -match '(?i)exclusion|exclude|exclu') -or ($assignmentType -match '(?i)exclusion|exclude')
    if ($isExclusion) {
        $backColor = [System.Drawing.Color]::FromArgb(111, 46, 52)
        $selectionBackColor = [System.Drawing.Color]::FromArgb(166, 77, 77)
    }
    else {
        $backColor = [System.Drawing.Color]::FromArgb(26, 83, 55)
        $selectionBackColor = [System.Drawing.Color]::FromArgb(45, 132, 93)
    }

    $EventArgs.CellStyle.BackColor = $backColor
    $EventArgs.CellStyle.ForeColor = [System.Drawing.Color]::White
    $EventArgs.CellStyle.SelectionBackColor = $selectionBackColor
    $EventArgs.CellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $EventArgs.CellStyle.Font = New-Object System.Drawing.Font($Grid.Font, [System.Drawing.FontStyle]::Bold)
}

function Set-DarkGridScrollBars {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Panel]$Container,
        [Parameter(Mandatory = $true)][hashtable]$Theme
    )

    $barSize = 13
    $Grid.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $Grid.Dock = 'None'
    $Grid.Location = New-Object System.Drawing.Point(0, 0)
    $Grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    $vBar = New-Object IntuneDarkScrollBarV1
    $vBar.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $vBar.Size = New-Object System.Drawing.Size($barSize, $barSize)
    $vBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    $hBar = New-Object IntuneDarkScrollBarV1
    $hBar.Orientation = [System.Windows.Forms.Orientation]::Horizontal
    $hBar.Height = $barSize
    $hBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    foreach ($bar in @($vBar, $hBar)) {
        $bar.TrackColor = $Theme.Window
        $bar.ThumbColor = $Theme.Accent
        $bar.ThumbHoverColor = [System.Drawing.Color]::FromArgb(96, 145, 198)
        $bar.ThumbPressedColor = $Theme.AccentDark
        $bar.BorderColor = $Theme.Border
    }

    $corner = New-Object System.Windows.Forms.Panel
    $corner.BackColor = $Theme.Window
    $corner.Size = New-Object System.Drawing.Size($barSize, $barSize)
    $corner.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    $syncing = $false

    $updateLayout = {
        $clientWidth = [Math]::Max(0, $Container.ClientSize.Width - $barSize)
        $clientHeight = [Math]::Max(0, $Container.ClientSize.Height - $barSize)
        $Grid.Size = New-Object System.Drawing.Size($clientWidth, $clientHeight)
        $vBar.Location = New-Object System.Drawing.Point($clientWidth, 0)
        $vBar.Size = New-Object System.Drawing.Size($barSize, $clientHeight)
        $hBar.Location = New-Object System.Drawing.Point(0, $clientHeight)
        $hBar.Size = New-Object System.Drawing.Size($clientWidth, $barSize)
        $corner.Location = New-Object System.Drawing.Point($clientWidth, $clientHeight)
    }.GetNewClosure()

    $updateRanges = {
        if ($syncing) { return }

        $visibleRows = 0
        try {
            $visibleRows = $Grid.DisplayedRowCount($false)
        }
        catch {
            $visibleRows = 0
        }

        $verticalMaximum = [Math]::Max(0, $Grid.RowCount - [Math]::Max(1, $visibleRows))
        $verticalValue = 0
        if ($Grid.RowCount -gt 0) {
            try {
                $verticalValue = [Math]::Max(0, $Grid.FirstDisplayedScrollingRowIndex)
            }
            catch {
                $verticalValue = 0
            }
        }
        $vBar.SetRange(0, $verticalMaximum, [Math]::Max(1, $visibleRows))
        $vBar.SetValue([Math]::Min($verticalValue, $verticalMaximum))

        $totalColumnWidth = 0
        foreach ($column in $Grid.Columns) {
            if ($column.Visible) {
                $totalColumnWidth += $column.Width
            }
        }

        $horizontalMaximum = [Math]::Max(0, $totalColumnWidth - $Grid.DisplayRectangle.Width)
        $hBar.SetRange(0, $horizontalMaximum, [Math]::Max(1, $Grid.DisplayRectangle.Width))
        $hBar.SetValue([Math]::Min($Grid.HorizontalScrollingOffset, $horizontalMaximum))
    }.GetNewClosure()

    $scrollGridVertical = {
        param($sender, $eventArgs)
        if ($syncing -or $Grid.RowCount -eq 0) { return }
        $syncing = $true
        try {
            $target = [Math]::Min($eventArgs.NewValue, [Math]::Max(0, $Grid.RowCount - 1))
            $Grid.FirstDisplayedScrollingRowIndex = $target
        }
        catch {
        }
        finally {
            $syncing = $false
            & $updateRanges
        }
    }.GetNewClosure()

    $scrollGridHorizontal = {
        param($sender, $eventArgs)
        if ($syncing) { return }
        $syncing = $true
        try {
            $Grid.HorizontalScrollingOffset = [Math]::Max(0, $eventArgs.NewValue)
        }
        catch {
        }
        finally {
            $syncing = $false
            & $updateRanges
        }
    }.GetNewClosure()

    $scrollGridMouseWheel = {
        param($sender, $eventArgs)
        if ($syncing -or $Grid.RowCount -eq 0 -or $eventArgs.Delta -eq 0) { return }

        $wheelLines = [System.Windows.Forms.SystemInformation]::MouseWheelScrollLines
        if ($wheelLines -lt 1 -or $wheelLines -gt 20) {
            $wheelLines = 3
        }

        $notches = [Math]::Max(1, [int][Math]::Round([Math]::Abs($eventArgs.Delta) / 120))
        $offset = $wheelLines * $notches
        if ($eventArgs.Delta -gt 0) {
            $offset = -$offset
        }

        $syncing = $true
        try {
            $current = [Math]::Max(0, $Grid.FirstDisplayedScrollingRowIndex)
            $target = [Math]::Max(0, [Math]::Min(($current + $offset), ($Grid.RowCount - 1)))
            $Grid.FirstDisplayedScrollingRowIndex = $target
        }
        catch {
        }
        finally {
            $syncing = $false
            & $updateRanges
        }
    }.GetNewClosure()

    $refreshBars = {
        & $updateLayout
        & $updateRanges
    }.GetNewClosure()

    $vBar.Add_Scroll($scrollGridVertical)
    $hBar.Add_Scroll($scrollGridHorizontal)
    $Grid.Add_MouseWheel($scrollGridMouseWheel)
    $Grid.Add_Scroll({ & $updateRanges }.GetNewClosure())
    $Grid.Add_RowsAdded({ & $updateRanges }.GetNewClosure())
    $Grid.Add_RowsRemoved({ & $updateRanges }.GetNewClosure())
    $Grid.Add_ColumnWidthChanged({ & $updateRanges }.GetNewClosure())
    $Grid.Add_ColumnStateChanged({ & $updateRanges }.GetNewClosure())
    $Grid.Add_SizeChanged({ & $updateRanges }.GetNewClosure())
    $Grid.Add_DataBindingComplete({ & $updateRanges }.GetNewClosure())
    $Container.Add_Resize($refreshBars)

    $Container.Controls.Add($Grid)
    $Container.Controls.Add($vBar)
    $Container.Controls.Add($hBar)
    $Container.Controls.Add($corner)
    & $refreshBars
    $Grid.BringToFront()
    $vBar.BringToFront()
    $hBar.BringToFront()
    $corner.BringToFront()
}

function Update-DarkGridScrollBars {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.DataGridView]$Grid
    )

    if (-not $Grid.Parent) { return }

    foreach ($control in $Grid.Parent.Controls) {
        if ($control -is [IntuneDarkScrollBarV1]) {
            $control.Invalidate()
        }
    }
}

function Enable-NativeDarkScrollBars {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control
    )

    [IntuneNativeThemeV2]::ApplyDarkScrollBars($Control)
}

function Set-DarkTextBoxScrollBars {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.TextBox]$TextBox,
        [Parameter(Mandatory = $true)][System.Windows.Forms.Panel]$Container,
        [Parameter(Mandatory = $true)][hashtable]$Theme
    )

    $barSize = 13
    $TextBox.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $TextBox.WordWrap = $false
    $TextBox.Dock = 'None'
    $TextBox.Location = New-Object System.Drawing.Point(0, 0)
    $TextBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    $vBar = New-Object IntuneDarkScrollBarV1
    $vBar.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $vBar.Size = New-Object System.Drawing.Size($barSize, $barSize)
    $vBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $vBar.TrackColor = $Theme.Window
    $vBar.ThumbColor = $Theme.Accent
    $vBar.ThumbHoverColor = [System.Drawing.Color]::FromArgb(96, 145, 198)
    $vBar.ThumbPressedColor = $Theme.AccentDark
    $vBar.BorderColor = $Theme.Border

    $hBar = New-Object IntuneDarkScrollBarV1
    $hBar.Orientation = [System.Windows.Forms.Orientation]::Horizontal
    $hBar.Height = $barSize
    $hBar.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $hBar.TrackColor = $Theme.Window
    $hBar.ThumbColor = $Theme.Accent
    $hBar.ThumbHoverColor = [System.Drawing.Color]::FromArgb(96, 145, 198)
    $hBar.ThumbPressedColor = $Theme.AccentDark
    $hBar.BorderColor = $Theme.Border

    $corner = New-Object System.Windows.Forms.Panel
    $corner.BackColor = $Theme.Window
    $corner.Size = New-Object System.Drawing.Size($barSize, $barSize)
    $corner.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    $syncing = $false
    $horizontalValue = 0

    $updateLayout = {
        $clientWidth = [Math]::Max(0, $Container.ClientSize.Width - $barSize)
        $clientHeight = [Math]::Max(0, $Container.ClientSize.Height - $barSize)
        $TextBox.Size = New-Object System.Drawing.Size($clientWidth, $clientHeight)
        $vBar.Location = New-Object System.Drawing.Point($clientWidth, 0)
        $vBar.Size = New-Object System.Drawing.Size($barSize, $clientHeight)
        $hBar.Location = New-Object System.Drawing.Point(0, $clientHeight)
        $hBar.Size = New-Object System.Drawing.Size($clientWidth, $barSize)
        $corner.Location = New-Object System.Drawing.Point($clientWidth, $clientHeight)
    }.GetNewClosure()

    $updateRanges = {
        if ($syncing) { return }

        $lineCount = [Math]::Max(1, $TextBox.Lines.Count)
        $lineHeight = [Math]::Max(1, $TextBox.Font.Height)
        $visibleLines = [Math]::Max(1, [int][Math]::Floor($TextBox.ClientSize.Height / $lineHeight))
        $maximum = [Math]::Max(0, $lineCount - $visibleLines)
        $value = [Math]::Min([IntuneNativeThemeV2]::GetFirstVisibleLine($TextBox), $maximum)

        $vBar.SetRange(0, $maximum, $visibleLines)
        $vBar.SetValue($value)

        $maxLineLength = 0
        foreach ($line in $TextBox.Lines) {
            if ($line.Length -gt $maxLineLength) {
                $maxLineLength = $line.Length
            }
        }

        $measure = [System.Windows.Forms.TextRenderer]::MeasureText('M', $TextBox.Font)
        $charWidth = [Math]::Max(1, $measure.Width)
        $visibleColumns = [Math]::Max(1, [int][Math]::Floor($TextBox.ClientSize.Width / $charWidth))
        $horizontalMaximum = [Math]::Max(0, $maxLineLength - $visibleColumns)
        $horizontalValue = [Math]::Min($horizontalValue, $horizontalMaximum)
        $hBar.SetRange(0, $horizontalMaximum, $visibleColumns)
        $hBar.SetValue($horizontalValue)
    }.GetNewClosure()

    $scrollTextBox = {
        param($sender, $eventArgs)
        if ($syncing) { return }

        $syncing = $true
        try {
            $current = [IntuneNativeThemeV2]::GetFirstVisibleLine($TextBox)
            [IntuneNativeThemeV2]::ScrollTextBox($TextBox, 0, $eventArgs.NewValue - $current)
        }
        finally {
            $syncing = $false
            & $updateRanges
        }
    }.GetNewClosure()

    $scrollTextBoxHorizontal = {
        param($sender, $eventArgs)
        if ($syncing) { return }

        $syncing = $true
        try {
            $delta = $eventArgs.NewValue - $horizontalValue
            [IntuneNativeThemeV2]::ScrollTextBox($TextBox, $delta, 0)
            $horizontalValue = $eventArgs.NewValue
        }
        finally {
            $syncing = $false
            & $updateRanges
        }
    }.GetNewClosure()

    $scrollTextBoxMouseWheel = {
        param($sender, $eventArgs)
        if ($syncing) { return }

        $wheelLines = [System.Windows.Forms.SystemInformation]::MouseWheelScrollLines
        if ($wheelLines -le 0) {
            $wheelLines = 3
        }

        $lineDelta = if ($eventArgs.Delta -gt 0) { -$wheelLines } else { $wheelLines }

        $syncing = $true
        try {
            [IntuneNativeThemeV2]::ScrollTextBox($TextBox, 0, $lineDelta)
        }
        finally {
            $syncing = $false
            & $updateRanges
        }
    }.GetNewClosure()

    $focusTextBox = {
        if ($TextBox.CanFocus) {
            $TextBox.Focus()
        }
    }.GetNewClosure()

    $refreshBar = {
        & $updateLayout
        & $updateRanges
    }.GetNewClosure()

    $vBar.Add_Scroll($scrollTextBox)
    $hBar.Add_Scroll($scrollTextBoxHorizontal)
    $TextBox.Add_TextChanged({ & $updateRanges }.GetNewClosure())
    $TextBox.Add_MouseWheel($scrollTextBoxMouseWheel)
    $TextBox.Add_MouseEnter($focusTextBox)
    $Container.Add_MouseEnter($focusTextBox)
    $TextBox.Add_KeyUp({ & $updateRanges }.GetNewClosure())
    $TextBox.Add_MouseUp({ & $updateRanges }.GetNewClosure())
    $TextBox.Add_Resize({ & $updateRanges }.GetNewClosure())
    $Container.Add_Resize($refreshBar)

    $Container.Controls.Add($TextBox)
    $Container.Controls.Add($vBar)
    $Container.Controls.Add($hBar)
    $Container.Controls.Add($corner)
    & $refreshBar
    $TextBox.BringToFront()
    $vBar.BringToFront()
    $hBar.BringToFront()
    $corner.BringToFront()
}

function Configure-ResultsGridColumns {
    if (-not $script:grid) { return }

    $script:grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $script:grid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::None
    $script:grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::AutoSize
    $script:grid.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False
    $theme = Get-DarkTheme
    $script:grid.DefaultCellStyle.BackColor = $theme.PanelAlt
    $script:grid.DefaultCellStyle.ForeColor = $theme.Text
    $script:grid.DefaultCellStyle.SelectionBackColor = $theme.Accent
    $script:grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $script:grid.AlternatingRowsDefaultCellStyle.BackColor = $theme.GridAlt
    $script:grid.AlternatingRowsDefaultCellStyle.ForeColor = $theme.Text
    $script:grid.BackgroundColor = $theme.GridBackground
    $script:grid.GridColor = $theme.Border
    Update-DarkGridScrollBars -Grid $script:grid
    $script:grid.EnableHeadersVisualStyles = $false
    $script:grid.ColumnHeadersDefaultCellStyle.BackColor = $theme.Title
    $script:grid.ColumnHeadersDefaultCellStyle.ForeColor = $theme.Text
    $script:grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font($script:grid.Font, [System.Drawing.FontStyle]::Bold)
    $script:grid.RowHeadersDefaultCellStyle.BackColor = $theme.Title
    $script:grid.ScrollBars = [System.Windows.Forms.ScrollBars]::None

    $widths = @{
        'Group' = 150
        'Category' = 180
        'Name' = 280
        'Type' = 240
        'Intent' = 120
        'Platform' = 130
        'Filter' = 140
        'Filter mode' = 110
        'Object ID' = 265
        'Assignment ID' = 330
        'Group ID' = 265
        'Assignment type' = 260
        'Match' = 210
        'Details' = 260
    }

    foreach ($column in $script:grid.Columns) {
        $column.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic
        $column.MinimumWidth = 80
        $column.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
        if ($column.Name -eq 'Match') {
            $column.HeaderText = 'Include / Exclude'
        }
        if ($widths.ContainsKey($column.Name)) {
            $column.Width = [int]$widths[$column.Name]
        }
    }
}

function Resolve-GroupsForAnalysis {
    param(
        [string[]]$GroupNames
    )

    $resolved = @()
    foreach ($name in $GroupNames) {
        try {
            $groups = @(Get-EntraGroupByName -DisplayName $name)
            if ($groups.Count -eq 0) {
                Write-UiLog -Message "No group found for '$name'." -Level Warn
                [System.Windows.Forms.MessageBox]::Show("No group found for '$name'.", 'Group not found', 'OK', 'Information') | Out-Null
                continue
            }

            $selected = Select-EntraGroup -Groups $groups
            if ($selected) {
                $resolved += $selected
            }
        }
        catch {
            Write-UiLog -Message $_.Exception.Message -Level Error
        }
    }
    return $resolved
}

function Invoke-GroupAnalysis {
    param(
        [Parameter(Mandatory = $true)][array]$Groups,
        [switch]$ClearExisting
    )

    if (-not (Test-GraphConnectionForAnalysis)) {
        return
    }

    if ($ClearExisting) {
        $script:ResultsTable.Clear()
    }

    $groupIndex = 0
    foreach ($group in $Groups) {
        Test-AnalysisCancellation
        $groupIndex++
        Set-UiStatus -Text "Analyzing $($group.DisplayName) ($groupIndex / $($Groups.Count))..." -Percent 25
        Write-UiLog -Message "Analysis started : $($group.DisplayName) ($($group.Id))." -Level Info

        try {
            Test-AnalysisCancellation
            Get-IntuneMobileAppAssignmentsByGroup -Group $group
            Test-AnalysisCancellation
            Set-UiStatus -Text "Configurations for $($group.DisplayName)..." -Percent 55
            Get-IntuneConfigurationAssignmentsByGroup -Group $group
            Test-AnalysisCancellation
            Set-UiStatus -Text "Endpoint security for $($group.DisplayName)..." -Percent 68
            Get-IntuneEndpointSecurityAssignmentsByGroup -Group $group
            Test-AnalysisCancellation
            Set-UiStatus -Text "Remediations for $($group.DisplayName)..." -Percent 74
            Get-IntuneRemediationAssignmentsByGroup -Group $group
            Test-AnalysisCancellation
            Set-UiStatus -Text "PowerShell scripts for $($group.DisplayName)..." -Percent 78
            Get-IntunePowerShellScriptAssignmentsByGroup -Group $group
            Test-AnalysisCancellation
            Set-UiStatus -Text "Compliance policies for $($group.DisplayName)..." -Percent 84
            Get-IntuneComplianceAssignmentsByGroup -Group $group
            Write-UiLog -Message "Analysis complete : $($group.DisplayName)." -Level Info
        }
        catch {
            if ($_.Exception -is [System.OperationCanceledException]) { throw }
            Write-UiLog -Message "Error during analysis of $($group.DisplayName) : $($_.Exception.Message)" -Level Error
        }
    }

    Test-AnalysisCancellation
    Update-Counts
    Update-FilterChoices
    Apply-LocalFilter
    Set-UiStatus -Text 'Analysis complete.' -Percent 100
}

function Invoke-DeviceAnalysis {
    param(
        [Parameter(Mandatory = $true)]$ManagedDevice,
        [switch]$ClearExisting
    )

    if (-not (Test-GraphConnectionForAnalysis)) {
        return
    }

    if ($ClearExisting) {
        $script:ResultsTable.Clear()
    }

    $deviceName = [string](Get-ObjectValue -InputObject $ManagedDevice -Name 'deviceName')
    Set-UiStatus -Text "Analyzing device $deviceName..." -Percent 20
    Write-UiLog -Message "Device analysis started : $(Get-ManagedDeviceDisplayText -Device $ManagedDevice)." -Level Info

    $directoryDevice = Resolve-DirectoryDeviceByManagedDevice -ManagedDevice $ManagedDevice
    if (-not $directoryDevice) {
        throw "Unable to find the Entra ID device object for '$deviceName'. Check that the device has an Azure AD device ID in Intune."
    }

    $deviceGroups = Get-TransitiveGroupsForDirectoryDevice -DirectoryDevice $directoryDevice
    Write-UiLog -Message "Transitive groups found for $deviceName : $($deviceGroups.Count)." -Level Info

    try {
        Test-AnalysisCancellation
        Get-IntuneMobileAppAssignmentsByDevice -ManagedDevice $ManagedDevice -DeviceGroups $deviceGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Configurations for $deviceName..." -Percent 55
        Get-IntuneConfigurationAssignmentsByDevice -ManagedDevice $ManagedDevice -DeviceGroups $deviceGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Endpoint security for $deviceName..." -Percent 68
        Get-IntuneEndpointSecurityAssignmentsByDevice -ManagedDevice $ManagedDevice -DeviceGroups $deviceGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Remediations for $deviceName..." -Percent 74
        Get-IntuneRemediationAssignmentsByDevice -ManagedDevice $ManagedDevice -DeviceGroups $deviceGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "PowerShell scripts for $deviceName..." -Percent 78
        Get-IntunePowerShellScriptAssignmentsByDevice -ManagedDevice $ManagedDevice -DeviceGroups $deviceGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Compliance policies for $deviceName..." -Percent 84
        Get-IntuneComplianceAssignmentsByDevice -ManagedDevice $ManagedDevice -DeviceGroups $deviceGroups
        Write-UiLog -Message "Device analysis complete : $deviceName." -Level Info
    }
    catch {
        if ($_.Exception -is [System.OperationCanceledException]) { throw }
        Write-UiLog -Message "Error during device analysis $deviceName : $($_.Exception.Message)" -Level Error
    }

    Test-AnalysisCancellation
    Update-Counts
    Update-FilterChoices
    Apply-LocalFilter
    Set-UiStatus -Text 'Device analysis complete.' -Percent 100
}

function Invoke-UserAnalysis {
    param(
        [Parameter(Mandatory = $true)]$DirectoryUser,
        [switch]$ClearExisting
    )

    if (-not (Test-GraphConnectionForAnalysis)) {
        return
    }

    if ($ClearExisting) {
        $script:ResultsTable.Clear()
    }

    $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'userPrincipalName')
    if ([string]::IsNullOrWhiteSpace($userPrincipalName)) {
        $userPrincipalName = [string](Get-ObjectValue -InputObject $DirectoryUser -Name 'mail')
    }

    Set-UiStatus -Text "Analyzing user $userPrincipalName..." -Percent 20
    Write-UiLog -Message "User analysis started : $(Get-DirectoryUserDisplayText -User $DirectoryUser)." -Level Info

    $userGroups = Get-TransitiveGroupsForDirectoryUser -DirectoryUser $DirectoryUser
    Write-UiLog -Message "Transitive groups found for $userPrincipalName : $($userGroups.Count)." -Level Info

    try {
        Test-AnalysisCancellation
        Get-IntuneMobileAppAssignmentsByUser -DirectoryUser $DirectoryUser -UserGroups $userGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Configurations for $userPrincipalName..." -Percent 55
        Get-IntuneConfigurationAssignmentsByUser -DirectoryUser $DirectoryUser -UserGroups $userGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Endpoint security for $userPrincipalName..." -Percent 68
        Get-IntuneEndpointSecurityAssignmentsByUser -DirectoryUser $DirectoryUser -UserGroups $userGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Remediations for $userPrincipalName..." -Percent 74
        Get-IntuneRemediationAssignmentsByUser -DirectoryUser $DirectoryUser -UserGroups $userGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "PowerShell scripts for $userPrincipalName..." -Percent 78
        Get-IntunePowerShellScriptAssignmentsByUser -DirectoryUser $DirectoryUser -UserGroups $userGroups
        Test-AnalysisCancellation
        Set-UiStatus -Text "Compliance policies for $userPrincipalName..." -Percent 84
        Get-IntuneComplianceAssignmentsByUser -DirectoryUser $DirectoryUser -UserGroups $userGroups
        Write-UiLog -Message "User analysis complete : $userPrincipalName." -Level Info
    }
    catch {
        if ($_.Exception -is [System.OperationCanceledException]) { throw }
        Write-UiLog -Message "Error during user analysis $userPrincipalName : $($_.Exception.Message)" -Level Error
    }

    Test-AnalysisCancellation
    Update-Counts
    Update-FilterChoices
    Apply-LocalFilter
    Set-UiStatus -Text 'User analysis complete.' -Percent 100
}

function Export-ResultsToCsv {
    [CmdletBinding()]
    param()

    if ($script:ResultsTable.Rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('No results to export.', 'Export CSV', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'CSV (*.csv)|*.csv'
    $dialog.FileName = 'Intune_Assignments_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss')

    if ($dialog.ShowDialog($script:form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $rows = foreach ($row in $script:ResultsTable.Rows) {
            $object = [ordered]@{}
            foreach ($column in $script:ResultsTable.Columns) {
                $object[$column.ColumnName] = [string]$row[$column.ColumnName]
            }
            [PSCustomObject]$object
        }

        $rows | Export-Csv -Path $dialog.FileName -NoTypeInformation -Encoding UTF8 -Delimiter ';'
        Write-UiLog -Message "CSV export complete : $($dialog.FileName)" -Level Info
        [System.Windows.Forms.MessageBox]::Show("CSV export complete.`r`n$($dialog.FileName)", 'Export CSV', 'OK', 'Information') | Out-Null
    }
    catch {
        Write-UiLog -Message "Unable to export CSV : $($_.Exception.Message)" -Level Error
    }
}

function Export-ResultsToExcel {
    [CmdletBinding()]
    param()

    if ($script:ResultsTable.Rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('No results to export.', 'Export Excel', 'OK', 'Information') | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'Excel (*.xlsx)|*.xlsx'
    $dialog.FileName = 'Intune_Assignments_{0}.xlsx' -f (Get-Date -Format 'yyyyMMdd_HHmmss')

    if ($dialog.ShowDialog($script:form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    $rows = foreach ($row in $script:ResultsTable.Rows) {
        $object = [ordered]@{}
        foreach ($column in $script:ResultsTable.Columns) {
            $object[$column.ColumnName] = [string]$row[$column.ColumnName]
        }
        [PSCustomObject]$object
    }

    try {
        if (Get-Module -ListAvailable -Name ImportExcel) {
            Import-Module ImportExcel -ErrorAction Stop
            $rows | Export-Excel -Path $dialog.FileName -WorksheetName 'Assignments' -AutoSize -FreezeTopRow -BoldTopRow -TableName 'IntuneAssignments' -ErrorAction Stop
        }
        else {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $workbook = $excel.Workbooks.Add()
            $sheet = $workbook.Worksheets.Item(1)
            $sheet.Name = 'Assignments'

            for ($c = 0; $c -lt $script:ResultsTable.Columns.Count; $c++) {
                $sheet.Cells.Item(1, $c + 1) = $script:ResultsTable.Columns[$c].ColumnName
            }

            $r = 2
            foreach ($row in $script:ResultsTable.Rows) {
                for ($c = 0; $c -lt $script:ResultsTable.Columns.Count; $c++) {
                    $sheet.Cells.Item($r, $c + 1) = [string]$row[$c]
                }
                $r++
            }

            [void]$sheet.UsedRange.EntireColumn.AutoFit()
            $workbook.SaveAs($dialog.FileName)
            $workbook.Close($true)
            $excel.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
        }

        Write-UiLog -Message "Excel export complete : $($dialog.FileName)" -Level Info
        [System.Windows.Forms.MessageBox]::Show("Excel export complete.`r`n$($dialog.FileName)", 'Export Excel', 'OK', 'Information') | Out-Null
    }
    catch {
        Write-UiLog -Message "Unable to export Excel : $($_.Exception.Message)" -Level Error
        [System.Windows.Forms.MessageBox]::Show("Unable to export Excel. Detail: $($_.Exception.Message)", 'Export Excel', 'OK', 'Warning') | Out-Null
    }
}

function New-RoundedRectanglePath {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Rectangle]$Bounds,
        [int]$Radius = 8
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [Math]::Max(1, $Radius * 2)
    $arc = New-Object System.Drawing.Rectangle($Bounds.X, $Bounds.Y, $diameter, $diameter)

    $path.AddArc($arc, 180, 90)
    $arc.X = $Bounds.Right - $diameter
    $path.AddArc($arc, 270, 90)
    $arc.Y = $Bounds.Bottom - $diameter
    $path.AddArc($arc, 0, 90)
    $arc.X = $Bounds.X
    $path.AddArc($arc, 90, 90)
    $path.CloseFigure()

    return $path
}

function Get-DarkTheme {
    return @{
        Window = [System.Drawing.Color]::FromArgb(18, 22, 27)
        Panel = [System.Drawing.Color]::FromArgb(24, 27, 31)
        PanelAlt = [System.Drawing.Color]::FromArgb(31, 35, 40)
        Field = [System.Drawing.Color]::FromArgb(13, 17, 23)
        Border = [System.Drawing.Color]::FromArgb(55, 62, 72)
        Text = [System.Drawing.Color]::FromArgb(232, 236, 241)
        MutedText = [System.Drawing.Color]::FromArgb(178, 186, 196)
        Accent = [System.Drawing.Color]::FromArgb(78, 122, 170)
        AccentDark = [System.Drawing.Color]::FromArgb(54, 85, 122)
        Secondary = [System.Drawing.Color]::FromArgb(73, 80, 90)
        Title = [System.Drawing.Color]::FromArgb(18, 22, 27)
        GridAlt = [System.Drawing.Color]::FromArgb(36, 41, 47)
        GridBackground = [System.Drawing.Color]::FromArgb(45, 51, 59)
    }
}

function Set-RoundedButtonStyle {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$Button,
        [int]$Radius = 8,
        [System.Drawing.Color]$BackColor = ([System.Drawing.Color]::FromArgb(54, 85, 122)),
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, $BackColor.R + 18),
        [Math]::Min(255, $BackColor.G + 18),
        [Math]::Min(255, $BackColor.B + 18)
    )
    $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
        [Math]::Max(0, $BackColor.R - 14),
        [Math]::Max(0, $BackColor.G - 14),
        [Math]::Max(0, $BackColor.B - 14)
    )
    $Button.BackColor = $BackColor
    $Button.ForeColor = $ForeColor
    $Button.UseVisualStyleBackColor = $false
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand

    $updateRegion = {
        param($sender, $eventArgs)
        if ($sender.Width -le 0 -or $sender.Height -le 0) { return }
        $bounds = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
        $path = New-RoundedRectanglePath -Bounds $bounds -Radius $Radius
        if ($sender.Region) {
            $sender.Region.Dispose()
        }
        $sender.Region = New-Object System.Drawing.Region($path)
        $path.Dispose()
    }

    $updateRegion = $updateRegion.GetNewClosure()
    $Button.Add_Resize($updateRegion)
    & $updateRegion $Button $null
}

function Update-GraphConnectionButtonStyle {
    param(
        [ValidateSet('Disconnected', 'Connecting', 'Connected')]
        [string]$State = $(if ($script:IsConnected) { 'Connected' } else { 'Disconnected' })
    )

    if (-not $script:btnConnect) { return }

    switch ($State) {
        'Connected' {
            $script:btnConnect.Text = 'Disconnect Graph'
            Set-RoundedButtonStyle -Button $script:btnConnect -BackColor ([System.Drawing.Color]::FromArgb(45, 132, 93))
        }
        'Connecting' {
            $script:btnConnect.Text = 'Connecting...'
            Set-RoundedButtonStyle -Button $script:btnConnect -BackColor ([System.Drawing.Color]::FromArgb(184, 111, 48))
        }
        default {
            $script:btnConnect.Text = 'Graph connection'
            Set-RoundedButtonStyle -Button $script:btnConnect -BackColor ([System.Drawing.Color]::FromArgb(166, 77, 77))
        }
    }
}

function Set-RoundedTabStyle {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.TabControl]$TabControl,
        [int]$Radius = 8
    )

    if (-not $TabControl) { return }

    $theme = Get-DarkTheme
    $TabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $TabControl.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $TabControl.ItemSize = New-Object System.Drawing.Size(138, 40)
    $TabControl.Padding = New-Object System.Drawing.Point(14, 4)
    $TabControl.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
    $TabControl.BackColor = $theme.Panel

    if ($TabControl -is [IntuneDarkTabControlV3]) {
        $TabControl.ThemeBack = $theme.Panel
        $TabControl.TabBack = $theme.PanelAlt
        $TabControl.SelectedBack = $theme.AccentDark
        $TabControl.BorderColor = $theme.Border
        $TabControl.AccentColor = $theme.Accent
        $TabControl.TextColor = $theme.MutedText
        $TabControl.SelectedTextColor = [System.Drawing.Color]::White
        $TabControl.CornerRadius = $Radius
        $TabControl.Invalidate()
        return
    }

    $drawTab = {
        param($sender, $eventArgs)

        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $isSelected = ($eventArgs.Index -eq $sender.SelectedIndex)
        $tabBounds = $sender.GetTabRect($eventArgs.Index)
        $tabBounds.Inflate(-3, -2)
        $tabBounds.Height += 2

        $theme = Get-DarkTheme
        $backColor = $theme.PanelAlt
        $borderColor = $theme.Border
        $textColor = $theme.MutedText
        if ($isSelected) {
            $backColor = $theme.AccentDark
            $borderColor = $theme.Accent
            $textColor = [System.Drawing.Color]::White
        }

        $path = New-RoundedRectanglePath -Bounds $tabBounds -Radius $Radius
        $brush = New-Object System.Drawing.SolidBrush($backColor)
        $pen = New-Object System.Drawing.Pen($borderColor, 1)
        $graphics.FillPath($brush, $path)
        $graphics.DrawPath($pen, $path)

        $textFlags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
        [System.Windows.Forms.TextRenderer]::DrawText($graphics, $sender.TabPages[$eventArgs.Index].Text, $sender.Font, $tabBounds, $textColor, $textFlags)

        $pen.Dispose()
        $brush.Dispose()
        $path.Dispose()
    }.GetNewClosure()
    $TabControl.Add_DrawItem($drawTab)
}

function Set-DarkControlStyle {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control,
        [Parameter(Mandatory = $true)][hashtable]$Theme
    )

    if ($Control -is [System.Windows.Forms.DataGridView]) {
        return
    }

    if ($Control.Tag -and ([string]$Control.Tag -eq 'MetricCard' -or [string]$Control.Tag -eq 'MetricAccent')) {
        return
    }

    if ($Control -is [System.Windows.Forms.TextBox] -or $Control -is [System.Windows.Forms.ListBox]) {
        $Control.BackColor = $Theme.Field
        $Control.ForeColor = $Theme.Text
        return
    }

    if ($Control -is [System.Windows.Forms.ComboBox]) {
        $Control.BackColor = $Theme.Field
        $Control.ForeColor = $Theme.Text
        return
    }

    if ($Control -is [System.Windows.Forms.Button]) {
        $Control.ForeColor = [System.Drawing.Color]::White
        return
    }

    if ($Control -is [System.Windows.Forms.Label] -or $Control -is [System.Windows.Forms.CheckBox] -or $Control -is [System.Windows.Forms.GroupBox]) {
        $Control.ForeColor = $Theme.Text
        if ($Control -is [System.Windows.Forms.Label]) {
            $Control.BackColor = [System.Drawing.Color]::Transparent
        }
        if ($Control -is [System.Windows.Forms.CheckBox]) {
            $Control.UseVisualStyleBackColor = $false
        }
    }

    if ($Control -is [System.Windows.Forms.Form]) {
        $Control.BackColor = $Theme.Window
    }
    elseif ($Control -is [System.Windows.Forms.TabPage]) {
        $Control.BackColor = $Theme.Panel
    }
    elseif ($Control -is [System.Windows.Forms.TabControl]) {
        $Control.BackColor = $Theme.Panel
    }
    elseif ($Control -is [System.Windows.Forms.Panel] -or $Control.GetType().Name -eq 'SplitterPanel' -or $Control -is [System.Windows.Forms.TableLayoutPanel] -or $Control -is [System.Windows.Forms.GroupBox] -or $Control -is [System.Windows.Forms.CheckBox]) {
        $Control.BackColor = $Theme.Panel
    }

    foreach ($child in $Control.Controls) {
        Set-DarkControlStyle -Control $child -Theme $Theme
    }
}

function Get-AppBasePath {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return (Split-Path -Parent $PSCommandPath)
    }

    return (Get-Location).Path
}

function Set-ApplicationIcon {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form
    )

    $iconPath = Join-Path (Get-AppBasePath) 'assets\microsoft-intune.png'
    if (-not (Test-Path -LiteralPath $iconPath)) { return }

    if (-not $script:AppIconBitmap) {
        $script:AppIconBitmap = [System.Drawing.Bitmap]::FromFile($iconPath)
    }

    if (-not $script:AppIcon) {
        $script:AppIcon = [System.Drawing.Icon]::FromHandle($script:AppIconBitmap.GetHicon())
    }

    $Form.Icon = $script:AppIcon
}

function Set-ApplicationTaskbarIdentity {
    [IntuneShellIdentityV1]::SetAppUserModelId('Macdoff.IntuneAssignmentsChecker')
}

function Set-ConnectedAccountDisplay {
    param(
        [string]$Account = ''
    )

    if (-not $script:lblConnectedAccount -or -not $script:lblConnectedAccountValue) { return }

    $script:lblConnectedAccount.Text = 'Account:'
    if ([string]::IsNullOrWhiteSpace($Account)) {
        $script:lblConnectedAccountValue.Text = 'not connected'
        $script:lblConnectedAccountValue.ForeColor = (Get-DarkTheme).MutedText
    }
    else {
        $script:lblConnectedAccountValue.Text = $Account
        $script:lblConnectedAccountValue.ForeColor = [System.Drawing.Color]::FromArgb(124, 200, 255)
    }
}

function Get-AppWindowBounds {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Control
    )

    $screen = [System.Windows.Forms.Screen]::FromControl($Control)
    $workingArea = [IntuneTaskbarInfoV2]::GetMaximizedBounds($screen.WorkingArea, $screen.Bounds)
    return (New-Object System.Drawing.Rectangle(
        $workingArea.X,
        $workingArea.Y,
        $workingArea.Width,
        $workingArea.Height
    ))
}

function Set-AppWindowMinimumSizeForBounds {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)][System.Drawing.Rectangle]$Bounds
    )

    if ($Form.Tag -is [hashtable]) {
        if (-not $Form.Tag.ContainsKey('OriginalMinimumSize')) {
            $Form.Tag['OriginalMinimumSize'] = $Form.MinimumSize
        }
        $originalMinimumSize = $Form.Tag['OriginalMinimumSize']
    }
    else {
        $originalMinimumSize = $Form.MinimumSize
    }

    $minimumWidth = [Math]::Min($originalMinimumSize.Width, $Bounds.Width)
    $minimumHeight = [Math]::Min($originalMinimumSize.Height, $Bounds.Height)
    $Form.MinimumSize = New-Object System.Drawing.Size($minimumWidth, $minimumHeight)
}

function Add-CustomTitleBar {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)][System.Windows.Forms.TableLayoutPanel]$MainLayout,
        [Parameter(Mandatory = $true)][hashtable]$Theme
    )

    $titleBar = New-Object System.Windows.Forms.Panel
    $titleBar.Dock = 'Fill'
    $titleBar.Margin = New-Object System.Windows.Forms.Padding(0)
    $titleBar.Padding = New-Object System.Windows.Forms.Padding(14, 0, 8, 0)
    $titleBar.BackColor = $Theme.Title
    $MainLayout.Controls.Add($titleBar, 0, 0)

    $accentLine = New-Object System.Windows.Forms.Panel
    $accentLine.Dock = 'Bottom'
    $accentLine.Height = 1
    $accentLine.BackColor = $Theme.Border
    $titleBar.Controls.Add($accentLine)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'Intune Assignments Finder'
    $titleLabel.AutoSize = $false
    $titleLabel.Location = New-Object System.Drawing.Point(14, 0)
    $titleLabel.Size = New-Object System.Drawing.Size(420, 38)
    $titleLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $titleLabel.ForeColor = $Theme.Text
    $titleLabel.BackColor = [System.Drawing.Color]::Transparent
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $titleBar.Controls.Add($titleLabel)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'X'
    $btnClose.Size = New-Object System.Drawing.Size(44, 30)
    $btnClose.Location = New-Object System.Drawing.Point(($titleBar.Width - 52), 4)
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.FlatAppearance.BorderSize = 0
    $btnClose.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(185, 45, 52)
    $btnClose.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(140, 32, 38)
    $btnClose.BackColor = $titleBar.BackColor
    $btnClose.ForeColor = $Theme.Text
    $btnClose.UseVisualStyleBackColor = $false
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleBar.Controls.Add($btnClose)

    $btnMaximize = New-Object System.Windows.Forms.Button
    $btnMaximize.Text = '□'
    $btnMaximize.Size = New-Object System.Drawing.Size(44, 30)
    $btnMaximize.Location = New-Object System.Drawing.Point(($titleBar.Width - 98), 4)
    $btnMaximize.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnMaximize.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnMaximize.FlatAppearance.BorderSize = 0
    $btnMaximize.FlatAppearance.MouseOverBackColor = $Theme.PanelAlt
    $btnMaximize.FlatAppearance.MouseDownBackColor = $Theme.AccentDark
    $btnMaximize.BackColor = $titleBar.BackColor
    $btnMaximize.ForeColor = $Theme.Text
    $btnMaximize.UseVisualStyleBackColor = $false
    $btnMaximize.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleBar.Controls.Add($btnMaximize)

    $btnMinimize = New-Object System.Windows.Forms.Button
    $btnMinimize.Text = '-'
    $btnMinimize.Size = New-Object System.Drawing.Size(44, 30)
    $btnMinimize.Location = New-Object System.Drawing.Point(($titleBar.Width - 144), 4)
    $btnMinimize.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnMinimize.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnMinimize.FlatAppearance.BorderSize = 0
    $btnMinimize.FlatAppearance.MouseOverBackColor = $Theme.PanelAlt
    $btnMinimize.FlatAppearance.MouseDownBackColor = $Theme.AccentDark
    $btnMinimize.BackColor = $titleBar.BackColor
    $btnMinimize.ForeColor = $Theme.Text
    $btnMinimize.UseVisualStyleBackColor = $false
    $btnMinimize.Cursor = [System.Windows.Forms.Cursors]::Hand
    $titleBar.Controls.Add($btnMinimize)

    $dragWindow = {
        param($sender, $eventArgs)
        if ($Form.Tag -is [hashtable] -and $Form.Tag.ContainsKey('IsCustomMaximized') -and $Form.Tag.IsCustomMaximized) {
            return
        }
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $eventArgs.Clicks -eq 1) {
            [IntuneWindowChromeV2]::DragWindow($Form)
        }
    }.GetNewClosure()

    $Form.Tag = @{
        IsCustomMaximized = $false
        RestoreBounds = [System.Drawing.Rectangle]::Empty
        OriginalMinimumSize = $Form.MinimumSize
    }

    $toggleMaximize = {
        if ($Form.Tag -is [hashtable] -and $Form.Tag.IsCustomMaximized) {
            $Form.MaximumSize = [System.Drawing.Size]::Empty
            $Form.Tag.IsCustomMaximized = $false
            if (-not $Form.Tag.RestoreBounds.IsEmpty) {
                Set-AppWindowMinimumSizeForBounds -Form $Form -Bounds (Get-AppWindowBounds -Control $Form)
                $Form.Bounds = $Form.Tag.RestoreBounds
            }
        }
        else {
            $Form.Tag.RestoreBounds = $Form.Bounds
            $Form.MaximumSize = [System.Drawing.Size]::Empty
            $Form.Tag.IsCustomMaximized = $true
            $workingArea = Get-AppWindowBounds -Control $Form
            Set-AppWindowMinimumSizeForBounds -Form $Form -Bounds $workingArea
            $Form.Bounds = $workingArea
        }
    }.GetNewClosure()

    $titleBar.Add_MouseDown($dragWindow)
    $titleLabel.Add_MouseDown($dragWindow)
    $titleBar.Add_MouseDoubleClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            & $toggleMaximize
        }
    }.GetNewClosure())
    $titleLabel.Add_MouseDoubleClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            & $toggleMaximize
        }
    }.GetNewClosure())
    $btnMinimize.Add_Click({
        $Form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    }.GetNewClosure())
    $btnMaximize.Add_Click($toggleMaximize)
    $btnClose.Add_Click({
        $Form.Close()
    }.GetNewClosure())

    $Form.Add_Resize({
        if ($Form.Tag -is [hashtable] -and $Form.Tag.IsCustomMaximized) {
            $btnMaximize.Text = '❐'
        }
        else {
            $btnMaximize.Text = '□'
        }
        if ($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal -and (-not ($Form.Tag -is [hashtable] -and $Form.Tag.IsCustomMaximized))) {
            $workingArea = Get-AppWindowBounds -Control $Form
            if ($Form.Width -gt $workingArea.Width -or $Form.Height -gt $workingArea.Height) {
                Set-AppWindowMinimumSizeForBounds -Form $Form -Bounds $workingArea
                $Form.Bounds = $workingArea
            }
        }
    }.GetNewClosure())

    $script:titleBar = $titleBar
    return $titleBar
}

function Add-WindowResizeGrips {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory = $true)][hashtable]$Theme
    )

    $grip = 4
    $corner = 12

    $addGrip = {
        param(
            [string]$Name,
            [System.Windows.Forms.AnchorStyles]$Anchor,
            [System.Windows.Forms.Cursor]$Cursor,
            [int]$HitTest
        )

        $panel = New-Object System.Windows.Forms.Panel
        $panel.Name = $Name
        $panel.BackColor = [System.Drawing.Color]::Transparent
        $panel.Cursor = $Cursor
        $panel.Anchor = $Anchor
        $panel.Add_MouseDown({
            param($sender, $eventArgs)
            if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                [IntuneWindowChromeV2]::ResizeWindow($Form, $HitTest)
            }
        }.GetNewClosure())
        $Form.Controls.Add($panel)
        return $panel
    }.GetNewClosure()

    $left = & $addGrip 'ResizeLeft' ([System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom) ([System.Windows.Forms.Cursors]::SizeWE) 10
    $right = & $addGrip 'ResizeRight' ([System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom) ([System.Windows.Forms.Cursors]::SizeWE) 11
    $top = & $addGrip 'ResizeTop' ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right) ([System.Windows.Forms.Cursors]::SizeNS) 12
    $bottom = & $addGrip 'ResizeBottom' ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right) ([System.Windows.Forms.Cursors]::SizeNS) 15
    $topLeft = & $addGrip 'ResizeTopLeft' ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left) ([System.Windows.Forms.Cursors]::SizeNWSE) 13
    $topRight = & $addGrip 'ResizeTopRight' ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right) ([System.Windows.Forms.Cursors]::SizeNESW) 14
    $bottomLeft = & $addGrip 'ResizeBottomLeft' ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left) ([System.Windows.Forms.Cursors]::SizeNESW) 16
    $bottomRight = & $addGrip 'ResizeBottomRight' ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right) ([System.Windows.Forms.Cursors]::SizeNWSE) 17

    $updateGrips = {
        $width = [Math]::Max(1, $Form.ClientSize.Width)
        $height = [Math]::Max(1, $Form.ClientSize.Height)

        $left.SetBounds(0, $corner, $grip, [Math]::Max(1, $height - ($corner * 2)))
        $right.SetBounds($width - $grip, $corner, $grip, [Math]::Max(1, $height - ($corner * 2)))
        $top.SetBounds($corner, 0, [Math]::Max(1, $width - ($corner * 2)), $grip)
        $bottom.SetBounds($corner, $height - $grip, [Math]::Max(1, $width - ($corner * 2)), $grip)
        $topLeft.SetBounds(0, 0, $corner, $corner)
        $topRight.SetBounds($width - $corner, 0, $corner, $corner)
        $bottomLeft.SetBounds(0, $height - $corner, $corner, $corner)
        $bottomRight.SetBounds($width - $corner, $height - $corner, $corner, $corner)

        foreach ($panel in @($left, $right, $top, $bottom, $topLeft, $topRight, $bottomLeft, $bottomRight)) {
            $customMaximized = ($Form.Tag -is [hashtable] -and $Form.Tag.ContainsKey('IsCustomMaximized') -and $Form.Tag.IsCustomMaximized)
            $panel.Visible = ($Form.WindowState -ne [System.Windows.Forms.FormWindowState]::Maximized -and -not $customMaximized)
            $panel.BringToFront()
        }
    }.GetNewClosure()

    $Form.Add_Resize($updateGrips)
    $Form.Add_Shown($updateGrips)
    & $updateGrips
}

function Get-DefaultGroupNamesFromFile {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:DefaultGroupListPath)) {
        Write-UiLog -Message "Group file not found : $($script:DefaultGroupListPath)." -Level Warn
        return @()
    }

    $names = @(
        Get-Content -LiteralPath $script:DefaultGroupListPath -ErrorAction Stop |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#') } |
            Select-Object -Unique
    )

    Write-UiLog -Message "Groups loaded from $($script:DefaultGroupListPath) : $($names.Count)." -Level Info
    return $names
}

function Update-DefaultGroupCombo {
    [CmdletBinding()]
    param(
        [switch]$ShowMessage
    )

    if (-not $script:cboDefaultGroups) {
        return
    }

    $groupNames = @(Get-DefaultGroupNamesFromFile)
    Set-CheckedComboBoxItems -ComboBox $script:cboDefaultGroups -Items $groupNames
    if ($ShowMessage -and $groupNames.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No groups loaded.`r`nCreate or complete the file : $($script:DefaultGroupListPath)", 'Group list', 'OK', 'Information') | Out-Null
    }
}

function Initialize-Ui {
    $theme = Get-DarkTheme
    $script:ResultsTable = New-ResultTable

    $script:form = New-Object IntuneResizableFormV1
    $script:form.Text = 'Intune Assignments Finder'
    $script:form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $script:form.ResizeBorderWidth = 8
    $script:form.MinimizeBox = $true
    $script:form.MaximizeBox = $true
    $script:form.StartPosition = 'Manual'
    $script:form.Size = New-Object System.Drawing.Size(1320, 860)
    $script:form.MinimumSize = New-Object System.Drawing.Size(1120, 760)
    $script:form.BackColor = $theme.Window
    Set-ApplicationIcon -Form $script:form
    $script:form.Add_Shown({
        $workingArea = Get-AppWindowBounds -Control $script:form
        $width = [Math]::Min($script:form.Width, $workingArea.Width)
        $height = [Math]::Min($script:form.Height, $workingArea.Height)
        $left = $workingArea.Left + [int][Math]::Floor(($workingArea.Width - $width) / 2)
        $top = $workingArea.Top + [int][Math]::Floor(($workingArea.Height - $height) / 2)
        $restoreBounds = New-Object System.Drawing.Rectangle($left, $top, $width, $height)
        if ($script:form.Tag -is [hashtable]) {
            $script:form.Tag.RestoreBounds = $restoreBounds
            $script:form.Tag.IsCustomMaximized = $false
        }
        Set-AppWindowMinimumSizeForBounds -Form $script:form -Bounds $workingArea
        $script:form.Bounds = $restoreBounds
    })

    $mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $mainLayout.Dock = 'Fill'
    $mainLayout.ColumnCount = 1
    $mainLayout.RowCount = 4
    $mainLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $mainLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$mainLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 258)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 50)))
    $script:form.Controls.Add($mainLayout)

    $topPanel = New-Object System.Windows.Forms.Panel
    $topPanel.Dock = 'Fill'
    $topPanel.Height = 258
    $topPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $topPanel.Padding = New-Object System.Windows.Forms.Padding(10)
    $topPanel.BackColor = $theme.Panel
    $mainLayout.Controls.Add($topPanel, 0, 1)

    $script:btnConnect = New-Object System.Windows.Forms.Button
    $script:btnConnect.Text = 'Graph connection'
    $script:btnConnect.Location = New-Object System.Drawing.Point(10, 12)
    $script:btnConnect.Size = New-Object System.Drawing.Size(150, 34)
    $script:btnConnect.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
    $topPanel.Controls.Add($script:btnConnect)

    $script:lblConnectedAccount = New-Object System.Windows.Forms.Label
    $script:lblConnectedAccount.Text = 'Account:'
    $script:lblConnectedAccount.Location = New-Object System.Drawing.Point(172, 15)
    $script:lblConnectedAccount.Size = New-Object System.Drawing.Size(74, 28)
    $script:lblConnectedAccount.ForeColor = $theme.Text
    $script:lblConnectedAccount.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
    $script:lblConnectedAccount.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $topPanel.Controls.Add($script:lblConnectedAccount)

    $script:lblConnectedAccountValue = New-Object System.Windows.Forms.Label
    $script:lblConnectedAccountValue.Text = 'not connected'
    $script:lblConnectedAccountValue.Location = New-Object System.Drawing.Point(246, 15)
    $script:lblConnectedAccountValue.Size = New-Object System.Drawing.Size(650, 28)
    $script:lblConnectedAccountValue.ForeColor = $theme.MutedText
    $script:lblConnectedAccountValue.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
    $script:lblConnectedAccountValue.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $topPanel.Controls.Add($script:lblConnectedAccountValue)

    $headerSeparator = New-Object System.Windows.Forms.Panel
    $headerSeparator.Location = New-Object System.Drawing.Point(10, 52)
    $headerSeparator.Size = New-Object System.Drawing.Size(1280, 4)
    $headerSeparator.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $headerSeparator.BackColor = $theme.AccentDark
    $topPanel.Controls.Add($headerSeparator)

    $script:analysisTabs = New-Object IntuneDarkTabControlV3
    $script:analysisTabs.Location = New-Object System.Drawing.Point(10, 66)
    $script:analysisTabs.Size = New-Object System.Drawing.Size(1280, 136)
    $script:analysisTabs.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    Set-RoundedTabStyle -TabControl $script:analysisTabs
    $topPanel.Controls.Add($script:analysisTabs)
    $analysisTabs = $script:analysisTabs

    $tabGroups = New-Object System.Windows.Forms.TabPage
    $tabGroups.Text = 'Groups'
    $tabGroups.BackColor = $theme.Panel
    $script:analysisTabs.Controls.Add($tabGroups)

    $tabDevice = New-Object System.Windows.Forms.TabPage
    $tabDevice.Text = 'Device'
    $tabDevice.BackColor = $theme.Panel
    $script:analysisTabs.Controls.Add($tabDevice)

    $tabUser = New-Object System.Windows.Forms.TabPage
    $tabUser.Text = 'User'
    $tabUser.BackColor = $theme.Panel
    $script:analysisTabs.Controls.Add($tabUser)

    $groupBoxDefault = New-Object System.Windows.Forms.GroupBox
    $groupBoxDefault.Text = 'Default groups'
    $groupBoxDefault.Location = New-Object System.Drawing.Point(8, 2)
    $groupBoxDefault.Size = New-Object System.Drawing.Size(650, 76)
    $tabGroups.Controls.Add($groupBoxDefault)

    $script:cboDefaultGroups = New-Object IntuneCheckedComboBoxV3
    $script:cboDefaultGroups.Location = New-Object System.Drawing.Point(14, 26)
    $script:cboDefaultGroups.Size = New-Object System.Drawing.Size(350, 24)
    $script:cboDefaultGroups.SetTheme($theme.Field, $theme.Text, $theme.Border)
    $groupBoxDefault.Controls.Add($script:cboDefaultGroups)

    $lblDefaultGroupsPath = New-Object System.Windows.Forms.Label
    $lblDefaultGroupsPath.Text = $script:DefaultGroupListPath
    $lblDefaultGroupsPath.Location = New-Object System.Drawing.Point(14, 53)
    $lblDefaultGroupsPath.Size = New-Object System.Drawing.Size(350, 18)
    $lblDefaultGroupsPath.AutoEllipsis = $true
    $groupBoxDefault.Controls.Add($lblDefaultGroupsPath)

    $script:btnReloadDefaultGroups = New-Object System.Windows.Forms.Button
    $script:btnReloadDefaultGroups.Text = 'Reload'
    $script:btnReloadDefaultGroups.Location = New-Object System.Drawing.Point(374, 22)
    $script:btnReloadDefaultGroups.Size = New-Object System.Drawing.Size(100, 30)
    $groupBoxDefault.Controls.Add($script:btnReloadDefaultGroups)

    $script:btnAnalyzeDefault = New-Object System.Windows.Forms.Button
    $script:btnAnalyzeDefault.Text = 'Analyze selection'
    $script:btnAnalyzeDefault.Location = New-Object System.Drawing.Point(484, 22)
    $script:btnAnalyzeDefault.Size = New-Object System.Drawing.Size(140, 30)
    $groupBoxDefault.Controls.Add($script:btnAnalyzeDefault)

    $groupBoxCustom = New-Object System.Windows.Forms.GroupBox
    $groupBoxCustom.Text = 'Custom group'
    $groupBoxCustom.Location = New-Object System.Drawing.Point(672, 2)
    $groupBoxCustom.Size = New-Object System.Drawing.Size(592, 76)
    $groupBoxCustom.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $tabGroups.Controls.Add($groupBoxCustom)

    $lblCustom = New-Object System.Windows.Forms.Label
    $lblCustom.Text = 'Group name'
    $lblCustom.Location = New-Object System.Drawing.Point(14, 22)
    $lblCustom.Size = New-Object System.Drawing.Size(94, 22)
    $groupBoxCustom.Controls.Add($lblCustom)

    $script:txtCustomGroup = New-Object System.Windows.Forms.TextBox
    $script:txtCustomGroup.Location = New-Object System.Drawing.Point(112, 19)
    $script:txtCustomGroup.Size = New-Object System.Drawing.Size(270, 24)
    $groupBoxCustom.Controls.Add($script:txtCustomGroup)

    $script:btnAnalyzeCustom = New-Object System.Windows.Forms.Button
    $script:btnAnalyzeCustom.Text = 'Search / Analyze'
    $script:btnAnalyzeCustom.Location = New-Object System.Drawing.Point(392, 16)
    $script:btnAnalyzeCustom.Size = New-Object System.Drawing.Size(170, 30)
    $groupBoxCustom.Controls.Add($script:btnAnalyzeCustom)

    $groupBoxDevice = New-Object System.Windows.Forms.GroupBox
    $groupBoxDevice.Text = 'Device search'
    $groupBoxDevice.Location = New-Object System.Drawing.Point(8, 2)
    $groupBoxDevice.Size = New-Object System.Drawing.Size(760, 76)
    $groupBoxDevice.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $tabDevice.Controls.Add($groupBoxDevice)

    $script:txtDeviceSearch = New-Object System.Windows.Forms.TextBox
    $script:txtDeviceSearch.Location = New-Object System.Drawing.Point(14, 25)
    $script:txtDeviceSearch.Size = New-Object System.Drawing.Size(430, 24)
    $groupBoxDevice.Controls.Add($script:txtDeviceSearch)

    $script:btnAnalyzeDevice = New-Object System.Windows.Forms.Button
    $script:btnAnalyzeDevice.Text = 'Search / Analyze device'
    $script:btnAnalyzeDevice.Location = New-Object System.Drawing.Point(458, 22)
    $script:btnAnalyzeDevice.Size = New-Object System.Drawing.Size(190, 30)
    $groupBoxDevice.Controls.Add($script:btnAnalyzeDevice)

    $lblDeviceHint = New-Object System.Windows.Forms.Label
    $lblDeviceHint.Text = 'Device name, serial number, Intune ID, or Azure AD device ID'
    $lblDeviceHint.Location = New-Object System.Drawing.Point(14, 52)
    $lblDeviceHint.Size = New-Object System.Drawing.Size(720, 18)
    $groupBoxDevice.Controls.Add($lblDeviceHint)

    $groupBoxUser = New-Object System.Windows.Forms.GroupBox
    $groupBoxUser.Text = 'User search'
    $groupBoxUser.Location = New-Object System.Drawing.Point(8, 2)
    $groupBoxUser.Size = New-Object System.Drawing.Size(760, 76)
    $groupBoxUser.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $tabUser.Controls.Add($groupBoxUser)

    $script:txtUserMail = New-Object System.Windows.Forms.TextBox
    $script:txtUserMail.Location = New-Object System.Drawing.Point(14, 25)
    $script:txtUserMail.Size = New-Object System.Drawing.Size(430, 24)
    $groupBoxUser.Controls.Add($script:txtUserMail)

    $script:btnAnalyzeUser = New-Object System.Windows.Forms.Button
    $script:btnAnalyzeUser.Text = 'Search / Analyze user'
    $script:btnAnalyzeUser.Location = New-Object System.Drawing.Point(458, 22)
    $script:btnAnalyzeUser.Size = New-Object System.Drawing.Size(190, 30)
    $groupBoxUser.Controls.Add($script:btnAnalyzeUser)

    $lblUserHint = New-Object System.Windows.Forms.Label
    $lblUserHint.Text = 'Email address or user UPN'
    $lblUserHint.Location = New-Object System.Drawing.Point(14, 52)
    $lblUserHint.Size = New-Object System.Drawing.Size(720, 18)
    $groupBoxUser.Controls.Add($lblUserHint)

    $resultPanel = New-Object System.Windows.Forms.Panel
    $resultPanel.Dock = 'Fill'
    $resultPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $resultPanel.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 0)
    $resultPanel.BackColor = $theme.Window
    $mainLayout.Controls.Add($resultPanel, 0, 2)

    $resultLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $resultLayout.Dock = 'Fill'
    $resultLayout.ColumnCount = 1
    $resultLayout.RowCount = 2
    $resultLayout.Margin = New-Object System.Windows.Forms.Padding(0)
    $resultLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    [void]$resultLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$resultLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 74)))
    [void]$resultLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $resultPanel.Controls.Add($resultLayout)

    $script:filterPanel = New-Object System.Windows.Forms.Panel
    $script:filterPanel.Location = New-Object System.Drawing.Point(10, 208)
    $script:filterPanel.Size = New-Object System.Drawing.Size(1280, 42)
    $script:filterPanel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $script:filterPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $script:filterPanel.Height = 42
    $script:filterPanel.BackColor = $theme.Panel
    $topPanel.Controls.Add($script:filterPanel)

    $lblFilter = New-Object System.Windows.Forms.Label
    $lblFilter.Text = 'Search'
    $lblFilter.Location = New-Object System.Drawing.Point(0, 12)
    $lblFilter.Size = New-Object System.Drawing.Size(48, 22)
    $script:filterPanel.Controls.Add($lblFilter)

    $script:txtResultFilter = New-Object System.Windows.Forms.TextBox
    $script:txtResultFilter.Location = New-Object System.Drawing.Point(52, 9)
    $script:txtResultFilter.Size = New-Object System.Drawing.Size(254, 24)
    $script:filterPanel.Controls.Add($script:txtResultFilter)

    $lblGroupFilter = New-Object System.Windows.Forms.Label
    $lblGroupFilter.Text = 'Group'
    $lblGroupFilter.Location = New-Object System.Drawing.Point(320, 12)
    $lblGroupFilter.Size = New-Object System.Drawing.Size(52, 22)
    $script:filterPanel.Controls.Add($lblGroupFilter)

    $script:cboGroupFilter = New-Object IntuneCheckedComboBoxV3
    $script:cboGroupFilter.SingularName = 'group'
    $script:cboGroupFilter.PluralName = 'groups'
    $script:cboGroupFilter.Location = New-Object System.Drawing.Point(376, 8)
    $script:cboGroupFilter.Size = New-Object System.Drawing.Size(160, 24)
    $script:cboGroupFilter.SetTheme($theme.Field, $theme.Text, $theme.Border)
    $script:filterPanel.Controls.Add($script:cboGroupFilter)

    $lblCategoryFilter = New-Object System.Windows.Forms.Label
    $lblCategoryFilter.Text = 'Category'
    $lblCategoryFilter.Location = New-Object System.Drawing.Point(552, 12)
    $lblCategoryFilter.Size = New-Object System.Drawing.Size(68, 22)
    $script:filterPanel.Controls.Add($lblCategoryFilter)

    $script:cboCategoryFilter = New-Object IntuneCheckedComboBoxV3
    $script:cboCategoryFilter.SingularName = 'category'
    $script:cboCategoryFilter.PluralName = 'categories'
    $script:cboCategoryFilter.Location = New-Object System.Drawing.Point(624, 8)
    $script:cboCategoryFilter.Size = New-Object System.Drawing.Size(190, 24)
    $script:cboCategoryFilter.SetTheme($theme.Field, $theme.Text, $theme.Border)
    $script:cboCategoryFilter.SetItems([string[]]@(
        'Application',
        'Configuration',
        'Compliance policy',
        'Settings catalog',
        'Administrative templates',
        'Endpoint security',
        'Firewall rules',
        'Remediation',
        'PowerShell script'
    ))
    $script:filterPanel.Controls.Add($script:cboCategoryFilter)

    $lblIntentFilter = New-Object System.Windows.Forms.Label
    $lblIntentFilter.Text = 'Intent'
    $lblIntentFilter.Location = New-Object System.Drawing.Point(830, 12)
    $lblIntentFilter.Size = New-Object System.Drawing.Size(48, 22)
    $script:filterPanel.Controls.Add($lblIntentFilter)

    $script:cboIntentFilter = New-Object IntuneCheckedComboBoxV3
    $script:cboIntentFilter.SingularName = 'intent'
    $script:cboIntentFilter.PluralName = 'intents'
    $script:cboIntentFilter.Location = New-Object System.Drawing.Point(882, 8)
    $script:cboIntentFilter.Size = New-Object System.Drawing.Size(130, 24)
    $script:cboIntentFilter.SetTheme($theme.Field, $theme.Text, $theme.Border)
    $script:filterPanel.Controls.Add($script:cboIntentFilter)

    $lblScopeFilter = New-Object System.Windows.Forms.Label
    $lblScopeFilter.Text = 'Scope'
    $lblScopeFilter.Location = New-Object System.Drawing.Point(1026, 12)
    $lblScopeFilter.Size = New-Object System.Drawing.Size(52, 22)
    $script:filterPanel.Controls.Add($lblScopeFilter)

    $script:cboScopeFilter = New-Object IntuneCheckedComboBoxV3
    $script:cboScopeFilter.SingularName = 'scope'
    $script:cboScopeFilter.PluralName = 'scopes'
    $script:cboScopeFilter.Location = New-Object System.Drawing.Point(1082, 8)
    $script:cboScopeFilter.Size = New-Object System.Drawing.Size(154, 24)
    $script:cboScopeFilter.SetTheme($theme.Field, $theme.Text, $theme.Border)
    $script:cboScopeFilter.SetItems([string[]]@('Include', 'Exclude'))
    $script:filterPanel.Controls.Add($script:cboScopeFilter)

    $btnClearResults = New-Object System.Windows.Forms.Button
    $btnClearResults.Text = 'Clear'
    $btnClearResults.Location = New-Object System.Drawing.Point(1255, 7)
    $btnClearResults.Size = New-Object System.Drawing.Size(50, 28)
    $script:filterPanel.Controls.Add($btnClearResults)

    $script:btnExportCsv = New-Object System.Windows.Forms.Button
    $script:btnExportCsv.Text = 'Export CSV'
    $script:btnExportCsv.Location = New-Object System.Drawing.Point(1320, 7)
    $script:btnExportCsv.Size = New-Object System.Drawing.Size(80, 28)
    $script:filterPanel.Controls.Add($script:btnExportCsv)

    $script:metricValueLabels = @{}
    $script:metricsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:metricsPanel.Dock = 'Fill'
    $script:metricsPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $script:metricsPanel.Padding = New-Object System.Windows.Forms.Padding(0)
    $script:metricsPanel.BackColor = $theme.Panel
    $script:metricsPanel.WrapContents = $true
    $script:metricsPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $script:metricsPanel.AutoScroll = $false
    $script:metricsPanel.Tag = 'MetricPanel'
    $script:metricsPanel.Add_Resize({ Update-MetricCardLayout })
    $resultLayout.Controls.Add($script:metricsPanel, 0, 0)

    New-MetricCard -Name 'Total' -Category 'Total' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Apps' -Category 'Application' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Config' -Category 'Configuration' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Compliance' -Category 'Compliance policy' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Settings' -Category 'Settings catalog' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Admin templates' -Category 'Administrative templates' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Endpoint' -Category 'Endpoint security' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Firewall' -Category 'Firewall rules' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Remediations' -Category 'Remediation' -Parent $script:metricsPanel -Theme $theme
    New-MetricCard -Name 'Scripts' -Category 'PowerShell script' -Parent $script:metricsPanel -Theme $theme

    $script:btnCancelAnalysis = New-Object System.Windows.Forms.Button
    $script:btnCancelAnalysis.Text = 'X'
    $script:btnCancelAnalysis.Size = New-Object System.Drawing.Size(68, 58)
    $script:btnCancelAnalysis.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 8)
    $script:btnCancelAnalysis.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $script:btnCancelAnalysis.Visible = $false
    $script:btnCancelAnalysis.Enabled = $false
    $script:btnCancelAnalysis.TabStop = $false
    $script:btnCancelAnalysis.Tag = 'CancelAnalysis'
    $script:metricsPanel.Controls.Add($script:btnCancelAnalysis)

    Update-MetricCardLayout

    $updateHeaderLayout = {
        if (-not $topPanel -or -not $analysisTabs -or -not $script:filterPanel) { return }
        if (-not $headerSeparator -or -not $tabGroups -or -not $groupBoxDefault -or -not $groupBoxCustom) { return }
        if (-not $groupBoxDevice -or -not $groupBoxUser) { return }

        $outerLeft = 10
        $outerRight = 10
        $outerWidth = [Math]::Max(1, $topPanel.ClientSize.Width - $outerLeft - $outerRight)
        $metricContentWidth = Get-MetricCardsContentWidth
        if ($metricContentWidth -le 0) {
            $metricContentWidth = $outerWidth
        }
        $filterWidth = [Math]::Min($outerWidth, $metricContentWidth)

        if ($headerSeparator.Left -ne $outerLeft -or $headerSeparator.Top -ne 52 -or $headerSeparator.Width -ne $outerWidth) {
            $headerSeparator.SetBounds($outerLeft, 52, $outerWidth, $headerSeparator.Height)
        }
        if ($analysisTabs.Left -ne $outerLeft -or $analysisTabs.Top -ne 66 -or $analysisTabs.Width -ne $outerWidth) {
            $analysisTabs.SetBounds($outerLeft, 66, $outerWidth, $analysisTabs.Height)
        }
        if ($script:filterPanel.Left -ne $outerLeft -or $script:filterPanel.Top -ne 208 -or $script:filterPanel.Width -ne $filterWidth) {
            $script:filterPanel.SetBounds($outerLeft, 208, $filterWidth, $script:filterPanel.Height)
        }

        $tabLeft = 8
        $tabGap = 14
        $tabWidth = [Math]::Max(1, $tabGroups.ClientSize.Width - ($tabLeft * 2))
        $firstGroupWidth = [Math]::Floor(($tabWidth - $tabGap) / 2)
        $secondGroupWidth = [Math]::Max(1, $tabWidth - $tabGap - $firstGroupWidth)

        $groupBoxDefault.Location = New-Object System.Drawing.Point($tabLeft, 2)
        $groupBoxDefault.Width = $firstGroupWidth
        $groupBoxCustom.Location = New-Object System.Drawing.Point(($tabLeft + $firstGroupWidth + $tabGap), 2)
        $groupBoxCustom.Width = $secondGroupWidth

        $script:btnAnalyzeDefault.Left = [Math]::Max(14, $groupBoxDefault.ClientSize.Width - $script:btnAnalyzeDefault.Width - 14)
        $script:btnReloadDefaultGroups.Left = [Math]::Max(14, $script:btnAnalyzeDefault.Left - $script:btnReloadDefaultGroups.Width - 10)
        $script:cboDefaultGroups.Width = [Math]::Max(120, $script:btnReloadDefaultGroups.Left - $script:cboDefaultGroups.Left - 10)
        $lblDefaultGroupsPath.Width = $script:cboDefaultGroups.Width

        $script:btnAnalyzeCustom.Left = [Math]::Max(112, $groupBoxCustom.ClientSize.Width - $script:btnAnalyzeCustom.Width - 14)
        $script:txtCustomGroup.Width = [Math]::Max(120, $script:btnAnalyzeCustom.Left - $script:txtCustomGroup.Left - 10)

        foreach ($box in @($groupBoxDevice, $groupBoxUser)) {
            $box.Location = New-Object System.Drawing.Point($tabLeft, 2)
            $box.Width = [Math]::Min(760, $tabWidth)
        }
        $lblDeviceHint.Width = [Math]::Max(120, $groupBoxDevice.ClientSize.Width - 28)
        $lblUserHint.Width = [Math]::Max(120, $groupBoxUser.ClientSize.Width - 28)

        $panelWidth = [Math]::Max(1, $script:filterPanel.ClientSize.Width)
        $metricRightEdge = Get-MetricCardsContentWidth
        if ($metricRightEdge -le 0) {
            $metricRightEdge = $panelWidth
        }
        $actionsRightEdge = [Math]::Min($panelWidth, $metricRightEdge)
        $script:btnExportCsv.Left = [Math]::Max(0, $actionsRightEdge - $script:btnExportCsv.Width)
        $btnClearResults.Left = [Math]::Max(0, $script:btnExportCsv.Left - $btnClearResults.Width - 12)

        $script:cboScopeFilter.Width = [Math]::Max(120, $btnClearResults.Left - $script:cboScopeFilter.Left - 12)
        $rightEdge = $script:cboScopeFilter.Left + $script:cboScopeFilter.Width
        $lblScopeFilter.Left = [Math]::Max(0, $script:cboScopeFilter.Left - $lblScopeFilter.Width - 4)
        $script:cboIntentFilter.Width = [Math]::Max(110, $lblScopeFilter.Left - $script:cboIntentFilter.Left - 16)
        $lblIntentFilter.Left = [Math]::Max(0, $script:cboIntentFilter.Left - $lblIntentFilter.Width - 4)
        $script:cboCategoryFilter.Width = [Math]::Max(160, $lblIntentFilter.Left - $script:cboCategoryFilter.Left - 16)
        $lblCategoryFilter.Left = [Math]::Max(0, $script:cboCategoryFilter.Left - $lblCategoryFilter.Width - 4)
        $script:cboGroupFilter.Width = [Math]::Max(140, $lblCategoryFilter.Left - $script:cboGroupFilter.Left - 16)
        $lblGroupFilter.Left = [Math]::Max(0, $script:cboGroupFilter.Left - $lblGroupFilter.Width - 4)
        $script:txtResultFilter.Width = [Math]::Max(160, $lblGroupFilter.Left - $script:txtResultFilter.Left - 16)
        $rightEdge | Out-Null
    }.GetNewClosure()

    $script:UpdateHeaderLayout = $updateHeaderLayout
    $topPanel.Add_Resize({ Invoke-HeaderLayout })
    $script:metricsPanel.Add_Resize({
        Update-MetricCardLayout
        Invoke-HeaderLayout
    })
    Invoke-HeaderLayout

    $script:splitResults = New-Object System.Windows.Forms.SplitContainer
    $script:splitResults.Dock = 'Fill'
    $script:splitResults.Orientation = 'Horizontal'
    $script:splitResults.SplitterDistance = 430
    $script:splitResults.Panel2MinSize = 120
    $script:splitResults.Margin = New-Object System.Windows.Forms.Padding(0)
    $resultLayout.Controls.Add($script:splitResults, 0, 1)

    $gridHost = New-Object System.Windows.Forms.Panel
    $gridHost.Dock = 'Fill'
    $gridHost.Margin = New-Object System.Windows.Forms.Padding(0)
    $gridHost.Padding = New-Object System.Windows.Forms.Padding(0)
    $gridHost.BackColor = $theme.Window

    $script:grid = New-Object System.Windows.Forms.DataGridView
    $script:grid.Dock = 'None'
    $script:grid.ReadOnly = $true
    $script:grid.AllowUserToAddRows = $false
    $script:grid.AllowUserToDeleteRows = $false
    $script:grid.BackgroundColor = [System.Drawing.Color]::FromArgb(45, 51, 59)
    $script:grid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $script:grid.GridColor = $theme.Border
    $script:grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $script:grid.SelectionMode = 'FullRowSelect'
    $script:grid.MultiSelect = $true
    $script:grid.RowHeadersVisible = $false
    $script:grid.AllowUserToResizeColumns = $true
    $script:grid.AllowUserToResizeRows = $false
    $script:grid.AllowUserToOrderColumns = $true
    $script:grid.ScrollBars = [System.Windows.Forms.ScrollBars]::None

    $script:BindingSource = New-Object System.Windows.Forms.BindingSource
    $script:BindingSource.DataSource = $script:ResultsTable
    $script:BindingSource.Sort = 'Category ASC'
    $script:grid.DataSource = $script:BindingSource
    Configure-ResultsGridColumns
    $script:grid.Add_DataBindingComplete({
        Configure-ResultsGridColumns
    })
    $script:grid.Add_CellFormatting({
        Apply-CategoryRowStyle -Grid $script:grid -EventArgs $_
        Apply-AssignmentMatchCellStyle -Grid $script:grid -EventArgs $_
    })
    Set-DarkGridScrollBars -Grid $script:grid -Container $gridHost -Theme $theme
    $script:splitResults.Panel1.Controls.Add($gridHost)

    $logHost = New-Object System.Windows.Forms.Panel
    $logHost.Dock = 'Fill'
    $logHost.Margin = New-Object System.Windows.Forms.Padding(0)
    $logHost.Padding = New-Object System.Windows.Forms.Padding(0)
    $logHost.BackColor = $theme.Window

    $script:txtLog = New-Object System.Windows.Forms.TextBox
    $script:txtLog.Dock = 'None'
    $script:txtLog.Multiline = $true
    $script:txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $script:txtLog.ReadOnly = $true
    $script:txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
    $script:txtLog.BackColor = $theme.Field
    $script:txtLog.ForeColor = $theme.Text
    $script:txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    Set-DarkTextBoxScrollBars -TextBox $script:txtLog -Container $logHost -Theme $theme
    $script:splitResults.Panel2.Controls.Add($logHost)

    $statusBar = New-Object System.Windows.Forms.Panel
    $statusBar.Dock = 'Fill'
    $statusBar.Margin = New-Object System.Windows.Forms.Padding(0)
    $statusBar.Padding = New-Object System.Windows.Forms.Padding(0, 10, 8, 6)
    $statusBar.BackColor = $theme.Title
    $statusBar.ForeColor = $theme.Text
    $mainLayout.Controls.Add($statusBar, 0, 3)
    $script:statusBar = $statusBar

    $script:lblStatus = New-Object System.Windows.Forms.Label
    $script:lblStatus.Text = 'Ready.'
    $script:lblStatus.ForeColor = $theme.Text
    $script:lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $script:lblStatus.AutoSize = $false
    $script:lblStatus.Margin = New-Object System.Windows.Forms.Padding(4, 0, 12, 0)
    $script:lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
    $script:lblStatus.BackColor = $statusBar.BackColor
    $script:lblStatus.Size = New-Object System.Drawing.Size(420, 32)
    $statusBar.Controls.Add($script:lblStatus)

    $script:progressBar = New-Object System.Windows.Forms.ProgressBar
    $script:progressBar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
    $script:progressBar.Size = New-Object System.Drawing.Size(1000, 32)
    $script:progressBar.Minimum = 0
    $script:progressBar.Maximum = 100
    $script:progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
    $statusBar.Controls.Add($script:progressBar)

    $statusLabel = $script:lblStatus
    $statusProgressBar = $script:progressBar
    $resizeStatusBar = {
        $availableStatusWidth = [Math]::Max(1, $statusBar.ClientSize.Width - $statusBar.Padding.Horizontal - 16)
        $progressWidth = [int][Math]::Floor($availableStatusWidth * 0.6)
        $labelWidth = [Math]::Max(120, $availableStatusWidth - $progressWidth - $statusLabel.Margin.Horizontal - $statusProgressBar.Margin.Horizontal)
        $availableHeight = [Math]::Max(12, $statusBar.ClientSize.Height - $statusBar.Padding.Vertical)
        $controlHeight = [Math]::Min(32, $availableHeight)
        $top = $statusBar.Padding.Top + [int][Math]::Floor(($availableHeight - $controlHeight) / 2)
        $labelLeft = $statusLabel.Margin.Left
        $progressLeft = $statusBar.ClientSize.Width - $statusBar.Padding.Right - $statusProgressBar.Margin.Right - $progressWidth
        $statusLabel.SetBounds([int]$labelLeft, [int]$top, [int]$labelWidth, [int]$controlHeight)
        $statusProgressBar.SetBounds([int]$progressLeft, [int]$top, [int]$progressWidth, [int]$controlHeight)
    }.GetNewClosure()
    $statusBar.Add_Resize($resizeStatusBar)
    & $resizeStatusBar

    Set-DarkControlStyle -Control $script:form -Theme $theme
    [void](Add-CustomTitleBar -Form $script:form -MainLayout $mainLayout -Theme $theme)
    Add-WindowResizeGrips -Form $script:form -Theme $theme
    Enable-NativeDarkScrollBars -Control $script:form

    $primaryButtonColor = $theme.AccentDark
    $secondaryButtonColor = $theme.Secondary
    foreach ($button in @($script:btnConnect, $script:btnAnalyzeDefault, $script:btnReloadDefaultGroups, $script:btnAnalyzeCustom, $script:btnAnalyzeDevice, $script:btnAnalyzeUser, $script:btnExportCsv)) {
        Set-RoundedButtonStyle -Button $button -BackColor $primaryButtonColor
    }
    Update-GraphConnectionButtonStyle -State Disconnected
    Set-RoundedButtonStyle -Button $script:btnCancelAnalysis -BackColor ([System.Drawing.Color]::FromArgb(166, 77, 77))
    Set-RoundedButtonStyle -Button $btnClearResults -BackColor $secondaryButtonColor
    Update-DefaultGroupCombo

    $script:AnalysisButtons = @($script:btnAnalyzeDefault, $script:btnAnalyzeCustom, $script:btnAnalyzeDevice, $script:btnAnalyzeUser)
    Set-AnalysisButtonsEnabled -Enabled $false

    $script:btnConnect.Add_Click({
        try {
            $script:VerboseLog = $true
            if ($script:IsConnected) {
                Disconnect-GraphSession
                return
            }

            Update-GraphConnectionButtonStyle -State Connecting
            Connect-Graph
            Set-AnalysisButtonsEnabled -Enabled $true
        }
        catch {
            $script:IsConnected = $false
            $script:ConnectedAccount = ''
            $script:ConnectedTenantId = ''
            Set-ConnectedAccountDisplay
            Set-AnalysisButtonsEnabled -Enabled $false
            Update-GraphConnectionButtonStyle -State Disconnected
            Write-UiLog -Message $_.Exception.Message -Level Error
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Graph connection error', 'OK', 'Error') | Out-Null
            Set-UiStatus -Text 'Connection error.' -Percent 0
        }
    })

    $script:btnCancelAnalysis.Add_Click({
        Request-AnalysisCancellation
    })

    $script:btnAnalyzeDefault.Add_Click({
        $analysisStarted = $false
        try {
            $selectedNames = @($script:cboDefaultGroups.GetCheckedItems())
            if ($selectedNames.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("Select at least one group from $($script:DefaultGroupListPath).", 'Analysis', 'OK', 'Information') | Out-Null
                return
            }

            if (-not (Test-GraphConnectionForAnalysis)) {
                return
            }

            Start-AnalysisRun
            $analysisStarted = $true
            $groups = @(Resolve-GroupsForAnalysis -GroupNames $selectedNames)
            Test-AnalysisCancellation
            if ($groups.Count -gt 0) {
                Invoke-GroupAnalysis -Groups $groups -ClearExisting
            }
        }
        catch {
            Handle-AnalysisException -ErrorRecord $_ -Title 'Analysis error' -StatusText 'Error during analysis.'
        }
        finally {
            if ($analysisStarted) {
                Stop-AnalysisRun
            }
        }
    })

    $script:btnReloadDefaultGroups.Add_Click({
        try {
            Update-DefaultGroupCombo -ShowMessage
        }
        catch {
            Show-UiError -ErrorRecord $_ -Title 'Group loading error'
        }
    })

    $script:btnAnalyzeCustom.Add_Click({
        $analysisStarted = $false
        try {
            $name = $script:txtCustomGroup.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                [System.Windows.Forms.MessageBox]::Show('Enter a group name.', 'Group search', 'OK', 'Information') | Out-Null
                return
            }

            if (-not (Test-GraphConnectionForAnalysis)) {
                return
            }

            Start-AnalysisRun
            $analysisStarted = $true
            $groups = @(Resolve-GroupsForAnalysis -GroupNames @($name))
            Test-AnalysisCancellation
            if ($groups.Count -gt 0) {
                Invoke-GroupAnalysis -Groups $groups -ClearExisting
            }
        }
        catch {
            Handle-AnalysisException -ErrorRecord $_ -Title 'Analysis error' -StatusText 'Error during analysis.'
        }
        finally {
            if ($analysisStarted) {
                Stop-AnalysisRun
            }
        }
    })

    $script:btnAnalyzeDevice.Add_Click({
        $analysisStarted = $false
        try {
            $search = $script:txtDeviceSearch.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($search)) {
                [System.Windows.Forms.MessageBox]::Show('Enter a device name, serial number, or ID.', 'Device search', 'OK', 'Information') | Out-Null
                return
            }

            if (-not (Test-GraphConnectionForAnalysis)) {
                return
            }

            Start-AnalysisRun
            $analysisStarted = $true
            $devices = @(Get-ManagedDevicesBySearch -SearchText $search)
            Test-AnalysisCancellation
            if ($devices.Count -eq 0) {
                Write-UiLog -Message "No device found for '$search'." -Level Warn
                [System.Windows.Forms.MessageBox]::Show("No device found for '$search'.", 'Device not found', 'OK', 'Information') | Out-Null
                return
            }

            $selectedDevice = Select-ManagedDevice -Devices $devices
            if ($selectedDevice) {
                Invoke-DeviceAnalysis -ManagedDevice $selectedDevice -ClearExisting
            }
        }
        catch {
            Handle-AnalysisException -ErrorRecord $_ -Title 'Device analysis error' -StatusText 'Error during device analysis.'
        }
        finally {
            if ($analysisStarted) {
                Stop-AnalysisRun
            }
        }
    })

    $script:btnAnalyzeUser.Add_Click({
        $analysisStarted = $false
        try {
            $mail = $script:txtUserMail.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($mail)) {
                [System.Windows.Forms.MessageBox]::Show('Enter an email address or UPN.', 'User search', 'OK', 'Information') | Out-Null
                return
            }

            if (-not (Test-GraphConnectionForAnalysis)) {
                return
            }

            Start-AnalysisRun
            $analysisStarted = $true
            $user = Resolve-DirectoryUserByMail -Mail $mail
            Test-AnalysisCancellation
            if (-not $user) {
                Write-UiLog -Message "No user found for '$mail'." -Level Warn
                [System.Windows.Forms.MessageBox]::Show("No user found for '$mail'.", 'User not found', 'OK', 'Information') | Out-Null
                return
            }

            Invoke-UserAnalysis -DirectoryUser $user -ClearExisting
        }
        catch {
            Handle-AnalysisException -ErrorRecord $_ -Title 'User analysis error' -StatusText 'Error during user analysis.'
        }
        finally {
            if ($analysisStarted) {
                Stop-AnalysisRun
            }
        }
    })

    $script:txtCustomGroup.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            $script:btnAnalyzeCustom.PerformClick()
        }
    })

    $script:txtDeviceSearch.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            $script:btnAnalyzeDevice.PerformClick()
        }
    })

    $script:txtUserMail.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            $script:btnAnalyzeUser.PerformClick()
        }
    })

    $script:txtResultFilter.Add_TextChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid local filter : $($_.Exception.Message)" -Level Warn
        }
    })

    $script:cboGroupFilter.Add_SelectedIndexChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid group filter : $($_.Exception.Message)" -Level Warn
        }
    })
    $script:cboGroupFilter.Add_TextChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid group filter : $($_.Exception.Message)" -Level Warn
        }
    })

    $script:cboCategoryFilter.Add_SelectedIndexChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid category filter : $($_.Exception.Message)" -Level Warn
        }
    })
    $script:cboCategoryFilter.Add_TextChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid category filter : $($_.Exception.Message)" -Level Warn
        }
    })

    $script:cboIntentFilter.Add_SelectedIndexChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid intent filter : $($_.Exception.Message)" -Level Warn
        }
    })
    $script:cboIntentFilter.Add_TextChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid intent filter : $($_.Exception.Message)" -Level Warn
        }
    })

    $script:cboScopeFilter.Add_SelectedIndexChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid scope filter : $($_.Exception.Message)" -Level Warn
        }
    })
    $script:cboScopeFilter.Add_TextChanged({
        try {
            Apply-LocalFilter
        }
        catch {
            Write-UiLog -Message "Invalid scope filter : $($_.Exception.Message)" -Level Warn
        }
    })

    $btnClearResults.Add_Click({
        $script:ResultsTable.Clear()
        Update-Counts
        Update-FilterChoices
        Apply-LocalFilter
        Set-UiStatus -Text 'Results cleared.' -Percent 0
    })

    $script:btnExportCsv.Add_Click({ Export-ResultsToCsv })

    $script:form.Add_Shown({
        if ($script:filterPanel) {
            $script:filterPanel.BringToFront()
        }
        Update-MetricCardLayout
        Invoke-HeaderLayout
        $logHeight = 180
        if ($script:splitResults.Height -gt ($logHeight + $script:splitResults.Panel1MinSize + $script:splitResults.SplitterWidth)) {
            $script:splitResults.SplitterDistance = $script:splitResults.Height - $logHeight - $script:splitResults.SplitterWidth
        }
        Configure-ResultsGridColumns
    })

    Update-Counts
    Write-UiLog -Message 'Interface initialized.' -Level Info
}

try {
    Set-ApplicationTaskbarIdentity
    Initialize-Ui
    [void]$script:form.ShowDialog()
}
catch {
    $fatalMessage = $_.Exception.Message
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
        $fatalMessage = "{0}`r`n`r`nLine: {1}" -f $fatalMessage, $_.InvocationInfo.ScriptLineNumber
        if (-not [string]::IsNullOrWhiteSpace($_.InvocationInfo.Line)) {
            $fatalMessage = "{0}`r`nCommand: {1}" -f $fatalMessage, $_.InvocationInfo.Line.Trim()
        }
    }
    [System.Windows.Forms.MessageBox]::Show($fatalMessage, 'Fatal error', 'OK', 'Error') | Out-Null
}


