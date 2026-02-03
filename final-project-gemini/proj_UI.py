import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import serial
import serial.tools.list_ports
import threading
import time

class FPGAMatrixToolV2:
    def __init__(self, root):
        self.root = root
        self.root.title("FPGA Matrix Terminal (Manual v1.0 Compliant)")
        self.root.geometry("1000x750")
        
        # --- 串口变量 ---
        self.ser = None
        self.is_connected = False
        self.stop_thread = False
        self.rx_buffer = ""  # 用于处理分包数据
        
        self.setup_ui()
        self.refresh_ports()

    def setup_ui(self):
        # ==================== 1. 顶部连接栏 ====================
        top_frame = tk.Frame(self.root, pady=10, bg="#f0f0f0", relief=tk.RAISED, bd=1)
        top_frame.pack(side=tk.TOP, fill=tk.X)
        
        tk.Label(top_frame, text="Port:", bg="#f0f0f0").pack(side=tk.LEFT, padx=5)
        self.combo_port = ttk.Combobox(top_frame, width=10)
        self.combo_port.pack(side=tk.LEFT, padx=5)
        
        # 手册要求：波特率严格锁定 115200 
        tk.Label(top_frame, text="Baud: 115200 (Fixed)", bg="#f0f0f0", fg="gray").pack(side=tk.LEFT, padx=5)
        
        self.btn_connect = tk.Button(top_frame, text="Open UART", command=self.toggle_connect, bg="lightgray")
        self.btn_connect.pack(side=tk.LEFT, padx=15)
        
        self.lbl_status = tk.Label(top_frame, text="Disconnected", fg="red", bg="#f0f0f0", font=("Arial", 10, "bold"))
        self.lbl_status.pack(side=tk.LEFT, padx=10)

        # ==================== 2. 功能标签页 ====================
        notebook = ttk.Notebook(self.root)
        notebook.pack(expand=True, fill=tk.BOTH, padx=10, pady=5)

        # --- Tab A: 创建矩阵 (Mode A) ---
        self.tab_create = tk.Frame(notebook)
        notebook.add(self.tab_create, text="Mode A: Create Matrix")
        self.setup_tab_create()

        # --- Tab B: 查看与查询 (Mode B) ---
        self.tab_view = tk.Frame(notebook)
        notebook.add(self.tab_view, text="Mode B: List/Query")
        self.setup_tab_view()

        # --- Tab C: 运算筛选 (Mode C) ---
        self.tab_calc = tk.Frame(notebook)
        notebook.add(self.tab_calc, text="Mode C: Calc/Filter")
        self.setup_tab_calc()

        # --- Tab D: 配置与工具 (Mode D) ---
        self.tab_config = tk.Frame(notebook)
        notebook.add(self.tab_config, text="Mode D: Config")
        self.setup_tab_config()

        # ==================== 3. 底部日志区 ====================
        log_frame = tk.LabelFrame(self.root, text="System Log & Raw UART", padx=5, pady=5)
        log_frame.pack(side=tk.BOTTOM, fill=tk.BOTH, padx=10, pady=5)
        
        self.txt_log = scrolledtext.ScrolledText(log_frame, height=8, state='disabled', font=("Consolas", 9))
        self.txt_log.pack(fill=tk.BOTH, expand=True)

    # -------------------- Tab A: 创建矩阵 --------------------
    def setup_tab_create(self):
        # 指引
        tk.Label(self.tab_create, text="Initialize Dimension (IDLE -> '1'~'5')", font=("Arial", 10, "bold")).pack(pady=5)
        
        # 维度选择
        frm_dim = tk.Frame(self.tab_create)
        frm_dim.pack()
        tk.Label(frm_dim, text="Rows (M):").pack(side=tk.LEFT)
        self.var_m = tk.Spinbox(frm_dim, from_=1, to=5, width=3, command=self.update_grid)
        self.var_m.pack(side=tk.LEFT, padx=5)
        tk.Label(frm_dim, text="Cols (N):").pack(side=tk.LEFT)
        self.var_n = tk.Spinbox(frm_dim, from_=1, to=5, width=3, command=self.update_grid)
        self.var_n.pack(side=tk.LEFT, padx=5)

        # 模式选择 (对应 SW[0])
        frm_mode = tk.LabelFrame(self.tab_create, text="Data Source Mode (Check Board SW[0])", padx=10, pady=10)
        frm_mode.pack(fill=tk.X, padx=20, pady=10)

        # 左侧：手动模式 SW[0]=0
        frm_man = tk.Frame(frm_mode)
        frm_man.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tk.Label(frm_man, text="Manual Mode (SW[0]=LOW)", fg="blue", font=("Arial", 9, "bold")).pack()
        
        self.grid_entries = []
        grid_frame = tk.Frame(frm_man)
        grid_frame.pack(pady=5)
        for r in range(5):
            row_e = []
            for c in range(5):
                e = tk.Entry(grid_frame, width=4, justify='center')
                e.grid(row=r, column=c, padx=1, pady=1)
                row_e.append(e)
            self.grid_entries.append(row_e)
        self.update_grid()

        tk.Button(frm_man, text="Send (Manual)", command=self.send_manual, bg="#e3f2fd").pack(pady=5)
        # 软件补零功能 [cite: 596]
        tk.Button(frm_man, text="Auto-Fill Zeros & Send", command=self.send_manual_autofill, bg="#fff9c4").pack(pady=2)

        ttk.Separator(frm_mode, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=10)

        # 右侧：随机模式 SW[0]=1
        frm_rnd = tk.Frame(frm_mode)
        frm_rnd.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tk.Label(frm_rnd, text="Random Mode (SW[0]=HIGH)", fg="green", font=("Arial", 9, "bold")).pack()
        
        tk.Label(frm_rnd, text="Count to Gen ('1' or '2'):").pack(pady=(20, 5))
        self.var_cnt = tk.Spinbox(frm_rnd, values=(1, 2), width=3)
        self.var_cnt.pack()
        
        tk.Button(frm_rnd, text="Send (Random)", command=self.send_random, bg="#e8f5e9").pack(pady=20)

    # -------------------- Tab B: 查看与查询 --------------------
    def setup_tab_view(self):
        # 顶部提示
        top_frm = tk.Frame(self.tab_view, bg="#fff3cd", pady=5)
        top_frm.pack(fill=tk.X)
        tk.Label(top_frm, text="NOTE: Press On-board BTN_S1 to trigger Query ", bg="#fff3cd", fg="#856404").pack()
        
        # 显示区域
        self.txt_view = scrolledtext.ScrolledText(self.tab_view, height=20, font=("Consolas", 10))
        self.txt_view.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        btn_frm = tk.Frame(self.tab_view)
        btn_frm.pack(pady=5)
        tk.Button(btn_frm, text="Clear View", command=lambda: self.txt_view.delete(1.0, tk.END)).pack()

    # -------------------- Tab C: 运算筛选 --------------------
    def setup_tab_calc(self):
        # 严重警告 
        warn_frm = tk.Frame(self.tab_calc, bg="#ffebee", pady=5)
        warn_frm.pack(fill=tk.X)
        tk.Label(warn_frm, text="WARNING: FPGA Logic Missing ALU Trigger (S_CALC).", bg="#ffebee", fg="red", font=("Arial", 10, "bold")).pack()
        tk.Label(warn_frm, text="UI can only FILTER matrices. Calculation must be implemented in FPGA.", bg="#ffebee", fg="red").pack()

        # 第一步：进入模式
        step1 = tk.LabelFrame(self.tab_calc, text="Step 1: Enter Filter Mode", padx=10, pady=10)
        step1.pack(fill=tk.X, padx=10, pady=5)
        tk.Button(step1, text="Send 'c' (Enter Mode)", command=lambda: self.send_char_seq('c')).pack(side=tk.LEFT)
        tk.Label(step1, text=" -> Watch LED 0xF1", fg="gray").pack(side=tk.LEFT)

        # 第二步：选择运算
        step2 = tk.LabelFrame(self.tab_calc, text="Step 2: Select Operator & Filter", padx=10, pady=10)
        step2.pack(fill=tk.X, padx=10, pady=5)
        
        self.var_op = tk.StringVar(value="1")
        tk.Radiobutton(step2, text="Addition ('1')", variable=self.var_op, value="1", command=self.update_calc_ui).grid(row=0, column=0, sticky='w')
        tk.Radiobutton(step2, text="Multiplication ('2')", variable=self.var_op, value="2", command=self.update_calc_ui).grid(row=1, column=0, sticky='w')

        # 动态维度输入
        self.frm_calc_dim = tk.Frame(step2)
        self.frm_calc_dim.grid(row=0, column=1, rowspan=2, padx=20)
        
        tk.Label(self.frm_calc_dim, text="Filter Dim:").pack(anchor='w')
        self.frm_dims_inputs = tk.Frame(self.frm_calc_dim)
        self.frm_dims_inputs.pack()
        
        # 初始化加法输入
        self.calc_entries = []
        self.update_calc_ui()
        
        tk.Button(step2, text="Send Filter Sequence", command=self.send_filter, bg="#e0f7fa").grid(row=0, column=2, rowspan=2, padx=10)

    # -------------------- Tab D: 配置与工具 --------------------
    def setup_tab_config(self):
        # 倒计时配置 [cite: 546]
        frm_cd = tk.LabelFrame(self.tab_config, text="Countdown Config (Mode D)", padx=10, pady=10)
        frm_cd.pack(fill=tk.X, padx=10, pady=10)
        
        tk.Label(frm_cd, text="Set Timeout (1-9s):").pack(side=tk.LEFT)
        self.var_timeout = tk.Spinbox(frm_cd, from_=1, to=9, width=3)
        self.var_timeout.pack(side=tk.LEFT, padx=5)
        tk.Button(frm_cd, text="Apply ('d' -> val)", command=self.send_countdown).pack(side=tk.LEFT, padx=10)

        # 全局清除指引 [cite: 489]
        frm_clr = tk.LabelFrame(self.tab_config, text="Global Clear (Hardware Only)", padx=10, pady=10)
        frm_clr.pack(fill=tk.X, padx=10, pady=10)
        tk.Label(frm_clr, text="To Clear All Memory:", fg="red", font=("Arial", 10, "bold")).pack(anchor='w')
        tk.Label(frm_clr, text="1. Set SW[7] = HIGH").pack(anchor='w')
        tk.Label(frm_clr, text="2. Press BTN_S1 (Confirm)").pack(anchor='w')
        tk.Label(frm_clr, text="Note: UART cannot trigger this action.").pack(anchor='w')

    # ==================== 逻辑处理 ====================

    def update_grid(self):
        """更新手动输入网格的启用状态"""
        try:
            m = int(self.var_m.get())
            n = int(self.var_n.get())
            for r in range(5):
                for c in range(5):
                    if r < m and c < n:
                        self.grid_entries[r][c].config(state='normal', bg='white')
                    else:
                        self.grid_entries[r][c].config(state='disabled', bg='#f0f0f0')
        except: pass

    def update_calc_ui(self):
        """根据加法/乘法更新维度输入框"""
        for w in self.frm_dims_inputs.winfo_children(): w.destroy()
        self.calc_entries = []
        
        op = self.var_op.get()
        if op == "1": # 加法 M, N [cite: 541]
            labels = ['M', 'N']
        else: # 乘法 M, N, P [cite: 542]
            labels = ['M', 'N', 'P']
            
        for l in labels:
            tk.Label(self.frm_dims_inputs, text=l).pack(side=tk.LEFT)
            e = tk.Entry(self.frm_dims_inputs, width=3)
            e.pack(side=tk.LEFT, padx=2)
            e.insert(0, "2")
            self.calc_entries.append(e)

    # --- 发送逻辑 ---

    def send_char_seq(self, *args):
        """发送字符序列，中间插入延时 """
        if not self.ser or not self.ser.is_open:
            messagebox.showerror("Error", "Port not open")
            return
        
        for char in args:
            self.ser.write(char.encode('ascii'))
            self.log(f"TX: {char}")
            time.sleep(0.01) # 10ms 延时

    def send_manual(self):
        """手动模式发送序列: M -> N -> Data..."""
        m = self.var_m.get()
        n = self.var_n.get()
        data = []
        
        # 收集数据
        try:
            for r in range(int(m)):
                for c in range(int(n)):
                    val = self.grid_entries[r][c].get()
                    if len(val) != 1 or not val.isdigit():
                        raise ValueError("Elements must be single digits 0-9")
                    data.append(val)
        except Exception as e:
            messagebox.showerror("Input Error", str(e))
            return

        # 发送序列 [cite: 508, 511, 516]
        self.send_char_seq(m, n, *data)

    def send_manual_autofill(self):
        """软件补零逻辑 [cite: 596]"""
        m = self.var_m.get()
        n = self.var_n.get()
        total = int(m) * int(n)
        data = []
        
        # 收集非空数据
        count = 0
        for r in range(int(m)):
            for c in range(int(n)):
                val = self.grid_entries[r][c].get()
                if val.isdigit():
                    data.append(val)
                    count += 1
                else:
                    break 
        
        # 补零
        zeros_needed = total - count
        if zeros_needed < 0: zeros_needed = 0
        data.extend(['0'] * zeros_needed)
        
        self.send_char_seq(m, n, *data)
        self.log(f"Auto-filled {zeros_needed} zeros.")

    def send_random(self):
        """随机模式发送序列: M -> N -> Count [cite: 522]"""
        m = self.var_m.get()
        n = self.var_n.get()
        cnt = self.var_cnt.get()
        self.send_char_seq(m, n, cnt)

    def send_filter(self):
        """筛选模式发送序列: c -> 1/2 -> Dims"""
        # 注意：这里我们假设用户已经按了“Enter Mode ('c')”，或者我们可以自动发
        # 但手册流程是先按c进入状态。为了安全，这里只发送筛选参数，或者包含整个流程。
        # 手册表格示例是分开的。但为了方便，我们可以连发：
        # c -> delay -> 1 -> delay -> M -> N
        
        op = self.var_op.get()
        dims = [e.get() for e in self.calc_entries]
        
        # 序列: 'c' (进入) -> op ('1'/'2') -> dims [cite: 583]
        self.send_char_seq('c', op, *dims)

    def send_countdown(self):
        """配置倒计时: d -> val [cite: 547, 549]"""
        val = self.var_timeout.get()
        self.send_char_seq('d', val)

    # --- 接收与解析 ---

    def rx_loop(self):
        while not self.stop_thread and self.ser and self.ser.is_open:
            try:
                if self.ser.in_waiting:
                    raw = self.ser.read(self.ser.in_waiting).decode('ascii', errors='ignore')
                    self.rx_buffer += raw
                    self.process_buffer()
                time.sleep(0.01)
            except:
                break

    def process_buffer(self):
        """解析协议格式: M*N&ID\nPayload... [cite: 564]"""
        while '\n' in self.rx_buffer:
            line, self.rx_buffer = self.rx_buffer.split('\n', 1)
            line = line.strip()
            if not line: continue
            
            self.log(f"RX: {line}")
            
            # 识别头信息 M*N&ID [cite: 565]
            if '*' in line and '&' in line:
                try:
                    dim_part, id_part = line.split('&')
                    rows, cols = dim_part.split('*')
                    matrix_id = id_part
                    self.render_matrix_header(rows, cols, matrix_id)
                except:
                    pass # 可能是 Payload 数据，忽略错误
            else:
                # 认为是矩阵数据行 [cite: 575]
                self.render_matrix_row(line)

    def render_matrix_header(self, r, c, mid):
        self.txt_view.insert(tk.END, f"\n=== Matrix ID: {mid} ({r}x{c}) ===\n", "header")
        self.txt_view.tag_config("header", foreground="blue", font=("Consolas", 10, "bold"))
        self.txt_view.see(tk.END)

    def render_matrix_row(self, row_str):
        # 简单的格式化显示
        self.txt_view.insert(tk.END, f"  [ {row_str} ]\n")
        self.txt_view.see(tk.END)

    def log(self, msg):
        self.txt_log.config(state='normal')
        self.txt_log.insert(tk.END, msg + "\n")
        self.txt_log.see(tk.END)
        self.txt_log.config(state='disabled')

    # --- 串口底层 ---

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.combo_port['values'] = ports
        if ports: self.combo_port.current(0)

    def toggle_connect(self):
        if not self.is_connected:
            try:
                self.ser = serial.Serial(self.combo_port.get(), 115200, timeout=0.1)
                self.is_connected = True
                self.lbl_status.config(text="Connected (115200)", fg="green")
                self.btn_connect.config(text="Close UART")
                self.stop_thread = False
                threading.Thread(target=self.rx_loop, daemon=True).start()
            except Exception as e:
                messagebox.showerror("Error", str(e))
        else:
            self.is_connected = False
            self.stop_thread = True
            if self.ser: self.ser.close()
            self.lbl_status.config(text="Disconnected", fg="red")
            self.btn_connect.config(text="Open UART")

if __name__ == "__main__":
    root = tk.Tk()
    app = FPGAMatrixToolV2(root)
    root.mainloop()