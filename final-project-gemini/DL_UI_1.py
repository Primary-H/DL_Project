import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import serial
import serial.tools.list_ports
import threading
import time

class MatrixFPGA_Professional:
    def __init__(self, root):
        self.root = root
        self.root.title("FPGA Matrix Operations Center (Ref: Manual V2)")
        self.root.geometry("1280x900") 
        
        # --- 通信变量 ---
        self.ser = None
        self.is_connected = False
        self.stop_thread = False
        self.rx_buffer = ""

        # --- 初始化界面 ---
        self.setup_layout()
        self.refresh_ports()

    def setup_layout(self):
        # ==================== 1. 顶部：硬件连接 ====================
        conn_frame = tk.Frame(self.root, pady=8, bg="#e1e1e1", relief=tk.RAISED, bd=1)
        conn_frame.pack(side=tk.TOP, fill=tk.X)
        
        tk.Label(conn_frame, text="UART Port:", bg="#e1e1e1", font=("Arial", 10, "bold")).pack(side=tk.LEFT, padx=10)
        self.combo_port = ttk.Combobox(conn_frame, width=15, state="readonly")
        self.combo_port.pack(side=tk.LEFT, padx=5)
        
        tk.Button(conn_frame, text="↻ Refresh", command=self.refresh_ports, relief=tk.FLAT, bg="#e1e1e1").pack(side=tk.LEFT, padx=2)
        tk.Label(conn_frame, text="|  Baud: 115200, 8N1  |", bg="#e1e1e1", fg="#555").pack(side=tk.LEFT, padx=15)
        
        self.btn_connect = tk.Button(conn_frame, text="CONNECT", command=self.toggle_connect, bg="#4caf50", fg="white", font=("Arial", 9, "bold"), width=12)
        self.btn_connect.pack(side=tk.LEFT, padx=10)
        
        self.lbl_status = tk.Label(conn_frame, text="OFFLINE", fg="red", bg="#e1e1e1", font=("Arial", 10, "bold"))
        self.lbl_status.pack(side=tk.LEFT, padx=10)

        # ==================== 2. 中部：业务流程 Tab ====================
        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(expand=True, fill=tk.BOTH, padx=10, pady=10)

        self.tab_input = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_input, text=" 1. Input Matrix ")
        self.setup_tab_input()

        self.tab_calc = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_calc, text=" 2. Calculation ")
        self.setup_tab_calc()

        self.tab_view = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_view, text=" 3. Memory View ")
        self.setup_tab_view()

        self.tab_config = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_config, text=" 4. Config ")
        self.setup_tab_config()

        # ==================== 3. 底部：实时日志 ====================
        log_frame = ttk.LabelFrame(self.root, text="System Log & Serial Monitor")
        log_frame.pack(side=tk.BOTTOM, fill=tk.BOTH, padx=10, pady=5)
        
        self.txt_log = scrolledtext.ScrolledText(log_frame, height=8, state='disabled', font=("Consolas", 9), bg="#1e1e1e", fg="#00ff00")
        self.txt_log.pack(fill=tk.BOTH, expand=True)

    # -----------------------------------------------------------
    # Tab 1: Input Flow (保持原逻辑)
    # -----------------------------------------------------------
    def setup_tab_input(self):
        main_frame = ttk.Frame(self.tab_input)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)

        step1 = ttk.LabelFrame(main_frame, text="Step 1: Define Dimension ")
        step1.pack(fill=tk.X, pady=5)
        ttk.Label(step1, text="Rows (M):").pack(side=tk.LEFT, padx=5, pady=10)
        self.in_row = ttk.Spinbox(step1, from_=1, to=5, width=3, command=self.update_input_grid)
        self.in_row.set(3)
        self.in_row.pack(side=tk.LEFT, padx=5)
        ttk.Label(step1, text="Cols (N):").pack(side=tk.LEFT, padx=5)
        self.in_col = ttk.Spinbox(step1, from_=1, to=5, width=3, command=self.update_input_grid)
        self.in_col.set(3)
        self.in_col.pack(side=tk.LEFT, padx=5)

        step2 = ttk.LabelFrame(main_frame, text="Step 2: Hardware Mode Check ")
        step2.pack(fill=tk.X, pady=10)
        self.var_input_mode = tk.StringVar(value="Manual")
        
        f_man = ttk.Frame(step2)
        f_man.pack(fill=tk.X, pady=5)
        ttk.Radiobutton(f_man, text="Manual Input (Require: SW[0] = OFF)", variable=self.var_input_mode, value="Manual", command=self.toggle_input_ui).pack(side=tk.LEFT, padx=10)
        
        f_auto = ttk.Frame(step2)
        f_auto.pack(fill=tk.X, pady=5)
        ttk.Radiobutton(f_auto, text="Auto Random (Require: SW[0] = ON)", variable=self.var_input_mode, value="Auto", command=self.toggle_input_ui).pack(side=tk.LEFT, padx=10)
        ttk.Label(f_auto, text="| Count to Generate:").pack(side=tk.LEFT)
        self.auto_count = ttk.Spinbox(f_auto, values=(1, 2), width=3)
        self.auto_count.set(1)
        self.auto_count.pack(side=tk.LEFT, padx=5)

        self.step3_frame = ttk.LabelFrame(main_frame, text="Step 3: Data Entry (Single Digit 0-9) ")
        self.step3_frame.pack(fill=tk.BOTH, expand=True, pady=10)
        self.input_cells = []
        self.grid_container = tk.Frame(self.step3_frame)
        self.grid_container.pack(pady=10)
        for r in range(5):
            row_widgets = []
            for c in range(5):
                e = tk.Entry(self.grid_container, width=5, justify='center', font=("Arial", 12))
                e.grid(row=r, column=c, padx=3, pady=3)
                row_widgets.append(e)
            self.input_cells.append(row_widgets)
        self.update_input_grid()

        ttk.Button(main_frame, text="SEND SEQUENCE TO FPGA", command=self.send_input_flow).pack(fill=tk.X, pady=10, ipady=5)

    def toggle_input_ui(self):
        mode = self.var_input_mode.get()
        state = 'normal' if mode == 'Manual' else 'disabled'
        bg = 'white' if mode == 'Manual' else '#f0f0f0'
        for r in range(5):
            for c in range(5):
                self.input_cells[r][c].config(state=state, bg=bg)
        self.auto_count.state(['!disabled'] if mode == 'Auto' else ['disabled'])

    def update_input_grid(self):
        try:
            m, n = int(self.in_row.get()), int(self.in_col.get())
            mode = self.var_input_mode.get()
            for r in range(5):
                for c in range(5):
                    widget = self.input_cells[r][c]
                    if r < m and c < n and mode == "Manual":
                        widget.config(state='normal', bg='white')
                    else:
                        widget.config(state='disabled', bg='#f0f0f0')
        except: pass

    # -----------------------------------------------------------
    # Tab 2: Calculation (UI 微调重点)
    # -----------------------------------------------------------
    def setup_tab_calc(self):
        # 左右分栏：左侧控制，右侧显示
        paned = ttk.PanedWindow(self.tab_calc, orient=tk.HORIZONTAL)
        paned.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        left_frame = ttk.Frame(paned, width=450)
        right_frame = ttk.Frame(paned)
        paned.add(left_frame, weight=1)
        paned.add(right_frame, weight=2)

        # --- 右侧：专用矩阵显示区 (使用 Consolas 等宽字体解决粘连) ---
        lbl_right = tk.Label(right_frame, text="Filtered Matrices / Results", font=("Arial", 10, "bold"), bg="#e0f7fa", pady=5)
        lbl_right.pack(fill=tk.X)
        self.calc_text = scrolledtext.ScrolledText(right_frame, font=("Consolas", 12), state='disabled', bg="#fafffd") 
        self.calc_text.pack(fill=tk.BOTH, expand=True)
        ttk.Button(right_frame, text="Clear View", command=lambda: self.clear_text(self.calc_text)).pack(fill=tk.X)

        # --- 左侧：控制流程 ---
        
        # 1. 基础设置
        p1 = ttk.LabelFrame(left_frame, text="1. Operation Setup")
        p1.pack(fill=tk.X, pady=5)
        
        ttk.Label(p1, text="Opcode:").pack(side=tk.LEFT, padx=5)
        self.calc_op = ttk.Combobox(p1, values=['1: Add (+)', '2: Multiply (*)', '3: Scalar (s*)', '4: Transpose (T)'], state="readonly", width=18)
        self.calc_op.current(0)
        self.calc_op.pack(side=tk.LEFT, padx=5, pady=10)

        # 2. 模式切换 (Manual vs Random)
        p_mode = ttk.LabelFrame(left_frame, text="2. Mode Selection")
        p_mode.pack(fill=tk.X, pady=5)
        
        self.calc_mode_var = tk.StringVar(value="Manual")
        # 增加 Command 绑定，点击时自动刷新 UI 布局
        ttk.Radiobutton(p_mode, text="Manual Filter (Standard)", variable=self.calc_mode_var, value="Manual", command=self.toggle_calc_ui).pack(anchor='w', padx=10, pady=2)
        ttk.Radiobutton(p_mode, text="Auto Random (Proto: 'r' Trigger)", variable=self.calc_mode_var, value="Random", command=self.toggle_calc_ui).pack(anchor='w', padx=10, pady=2)

        # --- Manual 模式容器 ---
        self.p_manual_container = tk.Frame(left_frame)
        # 默认显示
        self.p_manual_container.pack(fill=tk.X, pady=5)

        # Matrix A (Manual)
        self.p2 = ttk.LabelFrame(self.p_manual_container, text="3. Matrix A (Manual)")
        self.p2.pack(fill=tk.X, pady=5)
        f_dim_a = ttk.Frame(self.p2)
        f_dim_a.pack(fill=tk.X, pady=2)
        ttk.Label(f_dim_a, text="Dim:").pack(side=tk.LEFT)
        self.dim_a_r = ttk.Combobox(f_dim_a, values=list('12345'), width=2); self.dim_a_r.current(2)
        self.dim_a_r.pack(side=tk.LEFT)
        ttk.Label(f_dim_a, text="x").pack(side=tk.LEFT)
        self.dim_a_c = ttk.Combobox(f_dim_a, values=list('12345'), width=2); self.dim_a_c.current(2)
        self.dim_a_c.pack(side=tk.LEFT)
        ttk.Button(f_dim_a, text="Start & Filter A", command=lambda: self.start_manual_session("A")).pack(side=tk.LEFT, padx=5)

        f_id_a = ttk.Frame(self.p2)
        f_id_a.pack(fill=tk.X, pady=2)
        ttk.Label(f_id_a, text="Select ID:").pack(side=tk.LEFT)
        self.id_a = ttk.Entry(f_id_a, width=5)
        self.id_a.pack(side=tk.LEFT, padx=5)
        ttk.Button(f_id_a, text="Confirm A", command=lambda: self.send_uart(self.id_a.get(), "ID A")).pack(side=tk.LEFT)

        # Matrix B (Manual)
        self.p3 = ttk.LabelFrame(self.p_manual_container, text="4. Matrix B (If needed)")
        self.p3.pack(fill=tk.X, pady=5)
        f_dim_b = ttk.Frame(self.p3)
        f_dim_b.pack(fill=tk.X, pady=2)
        ttk.Label(f_dim_b, text="Dim:").pack(side=tk.LEFT)
        self.dim_b_r = ttk.Combobox(f_dim_b, values=list('12345'), width=2); self.dim_b_r.current(2)
        self.dim_b_r.pack(side=tk.LEFT)
        ttk.Label(f_dim_b, text="x").pack(side=tk.LEFT)
        self.dim_b_c = ttk.Combobox(f_dim_b, values=list('12345'), width=2); self.dim_b_c.current(2)
        self.dim_b_c.pack(side=tk.LEFT)
        ttk.Button(f_dim_b, text="Filter B", command=lambda: self.send_dims(self.dim_b_r.get(), self.dim_b_c.get())).pack(side=tk.LEFT, padx=5)
        
        f_id_b = ttk.Frame(self.p3)
        f_id_b.pack(fill=tk.X, pady=2)
        ttk.Label(f_id_b, text="Select ID:").pack(side=tk.LEFT)
        self.id_b = ttk.Entry(f_id_b, width=5)
        self.id_b.pack(side=tk.LEFT, padx=5)
        ttk.Button(f_id_b, text="Confirm B", command=lambda: self.send_uart(self.id_b.get(), "ID B")).pack(side=tk.LEFT)

        # --- Random 模式容器 (独立的) ---
        self.p_random_container = tk.Frame(left_frame)
        # 默认隐藏，通过 toggle_calc_ui 控制
        
        # 显眼的大按钮
        self.btn_rand_exec = tk.Button(self.p_random_container, text="🎲 EXECUTE RANDOM CALC 🎲", 
                             bg="#9c27b0", fg="white", font=("Arial", 12, "bold"),
                             command=self.trigger_random_calc)
        self.btn_rand_exec.pack(fill=tk.X, ipady=15, pady=20)
        
        lbl_hint = tk.Label(self.p_random_container, text="Sequence:\n1. Sends 'c' (Calc Mode)\n2. Sends Opcode\n3. Sends 'r' (Auto Search)", 
                            fg="#555", justify=tk.LEFT, bg="#f3e5f5", relief=tk.SUNKEN, padx=10, pady=10)
        lbl_hint.pack(fill=tk.X)

    def toggle_calc_ui(self):
        """互斥显示：根据单选框切换 Random 按钮或 Manual 输入框"""
        mode = self.calc_mode_var.get()
        if mode == "Manual":
            self.p_random_container.pack_forget() # 隐藏随机
            self.p_manual_container.pack(fill=tk.X, pady=5) # 显示手动
        else:
            self.p_manual_container.pack_forget() # 隐藏手动
            self.p_random_container.pack(fill=tk.X, pady=10) # 显示随机

    # -----------------------------------------------------------
    # Tab 3 & 4
    # -----------------------------------------------------------
    def setup_tab_view(self):
        f = ttk.Frame(self.tab_view)
        f.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        info = tk.Label(f, text="[INFO] Press BTN_S1 on FPGA to List All Matrices", font=("Arial", 11), bg="#e3f2fd", pady=5)
        info.pack(fill=tk.X, pady=5)
        self.view_text = scrolledtext.ScrolledText(f, font=("Consolas", 10), height=15)
        self.view_text.pack(fill=tk.BOTH, expand=True)
        ttk.Button(f, text="Clear", command=lambda: self.clear_text(self.view_text)).pack(pady=5)

    def setup_tab_config(self):
        f = ttk.Frame(self.tab_config)
        f.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        lf = ttk.LabelFrame(f, text="Error Timeout Configuration")
        lf.pack(fill=tk.X, pady=10)
        
        ttk.Label(lf, text="Value (5-15s):").pack(side=tk.LEFT, padx=10, pady=20)
        self.conf_timeout = ttk.Spinbox(lf, from_=5, to=15, width=5)
        self.conf_timeout.set(10)
        self.conf_timeout.pack(side=tk.LEFT)
        
        ttk.Button(lf, text="Set Timeout (Send 'd' -> val)", 
                   command=lambda: self.send_seq('d', self.conf_timeout.get())).pack(side=tk.LEFT, padx=20)

    # ==================== 逻辑处理 ====================

    def start_manual_session(self, target="A"):
        """手动流程：c -> Op -> Dims (触发列表显示)"""
        if not self.check_connection(): return
        self.clear_text(self.calc_text)
        self.append_text(self.calc_text, f">>> Manual Filter Start [{target}]...\n")
        
        # 1. Enter Calc Mode ('c')
        self.send_uart('c', "CMD: Calc Mode")
        time.sleep(0.1) # 增加延时保证 FPGA 状态跳转
        
        # 2. Send Opcode
        op_char = self.calc_op.get()[0]
        self.send_uart(op_char, f"CMD: Op {op_char}")
        time.sleep(0.1)
        
        # 3. Send Dimensions for A 
        r, c = self.dim_a_r.get(), self.dim_a_c.get()
        self.send_dims(r, c)

    def trigger_random_calc(self):
        """随机流程：c -> Op -> r (自动计算)"""
        if not self.check_connection(): return
        self.clear_text(self.calc_text)
        self.append_text(self.calc_text, ">>> Starting Random Calculation...\n")
        
        # 1. Enter Calc Mode
        self.send_uart('c', "CMD: Calc Mode")
        time.sleep(0.1) # 必要延时
        
        # 2. Send Opcode
        op_char = self.calc_op.get()[0]
        self.send_uart(op_char, f"CMD: Op {op_char}")
        time.sleep(0.1) # 等待 FSM 进入 S_FLOW_GET_M 状态
        
        # 3. Send 'r' to trigger auto-search (对应 FSM: S_FLOW_GET_M -> check 'r')
        self.send_uart('r', "CMD: Random Trigger")

    def send_input_flow(self):
        if not self.check_connection(): return
        mode = self.var_input_mode.get()
        required_sw = "OFF (0)" if mode == "Manual" else "ON (1)"
        if not messagebox.askyesno("Hardware Check", f"Is SW[0] set to {required_sw} on the FPGA?"):
            return

        m, n = self.in_row.get(), self.in_col.get()
        self.send_uart(m, "Row M"); time.sleep(0.05)
        self.send_uart(n, "Col N"); time.sleep(0.05)
        
        if mode == "Manual":
            data_str = ""
            for r in range(int(m)):
                for c in range(int(n)):
                    val = self.input_cells[r][c].get()
                    if not val.isdigit(): val = '0'
                    data_str += val
            for char in data_str:
                self.send_uart(char, f"Data {char}")
                time.sleep(0.02)
        else:
            self.send_uart(self.auto_count.get(), "Auto Count")

    def send_dims(self, r, c):
        self.send_uart(r, "Dim Row"); time.sleep(0.05)
        self.send_uart(c, "Dim Col")
        self.append_text(self.calc_text, f"\n--- Filtering {r}x{c} ---\n")

    def send_seq(self, *args):
        for arg in args:
            self.send_uart(arg)
            time.sleep(0.05)

    # ==================== 通信与解析 (Formatting Fix) ====================

    def check_connection(self):
        if not self.ser or not self.ser.is_open:
            messagebox.showerror("Error", "Port Not Connected")
            return False
        return True

    def toggle_connect(self):
        if self.is_connected:
            self.stop_thread = True
            if self.ser: self.ser.close()
            self.is_connected = False
            self.btn_connect.config(text="CONNECT", bg="#4caf50")
            self.lbl_status.config(text="OFFLINE", fg="red")
        else:
            try:
                p = self.combo_port.get()
                self.ser = serial.Serial(p, 115200, timeout=0.1)
                self.is_connected = True
                self.stop_thread = False
                self.btn_connect.config(text="DISCONNECT", bg="#f44336")
                self.lbl_status.config(text="ONLINE", fg="green")
                threading.Thread(target=self.rx_loop, daemon=True).start()
            except Exception as e:
                messagebox.showerror("Conn Error", str(e))

    def rx_loop(self):
        while not self.stop_thread and self.ser and self.ser.is_open:
            try:
                if self.ser.in_waiting:
                    raw = self.ser.read(self.ser.in_waiting).decode('ascii', errors='ignore')
                    self.rx_buffer += raw
                    self.process_buffer()
                time.sleep(0.01)
            except: break

    def process_buffer(self):
        """
        [修复版解析器]
        核心逻辑：FPGA 发送的数据以换行符 \n (0x0A) 结束一行。
        为了防止数字粘连，我们必须按行解析，并重新格式化数字间距。
        """
        while '\n' in self.rx_buffer:
            # 1. 提取完整的一行
            line_raw, self.rx_buffer = self.rx_buffer.split('\n', 1)
            line = line_raw.strip() # 去除首尾空白
            if not line: continue
            
            # 日志记录原始数据
            self.log_msg(f"RX: {line}", is_rx=True)
            
            display_text = ""
            
            # --- Case 1: Header 识别 (M*N&ID) ---
            if '*' in line and '&' in line:
                # 处理可能的情况: "3*3&0" 或 "3*3&0[1 2"
                # 简单粗暴的处理：如果是 Header，直接美化显示
                display_text = f"\n{'-'*10} {line} {'-'*10}\n"

            # --- Case 2: 矩阵数据行识别 ---
            # 特征：包含数字，且不包含特殊字母（除了可能的 hex A-F，但矩阵通常是十进制）
            elif self.is_matrix_row(line):
                # 关键修复：重新格式化，解决粘连
                display_text = self.format_matrix_row(line)
                
            # --- Case 3: 其他文本 ---
            else:
                display_text = f"{line}\n"

            # 分发到 Text 控件
            if display_text:
                self.append_text(self.view_text, display_text)
                self.append_text(self.calc_text, display_text)

    def is_matrix_row(self, line):
        """判断是否为矩阵数据行：由数字、负号、空格组成"""
        # 移除常见符号，检查剩余是否全是数字
        valid_chars = set("0123456789- []")
        if not line: return False
        # 检查是否包含非法字符
        if not all(c in valid_chars for c in line):
            return False
        # 必须包含数字
        return any(c.isdigit() for c in line)

    def format_matrix_row(self, line):
        """
        [格式化核心]
        输入: "1 2 -30" 或 "123" (粘连情况通常会有空格分隔，但视觉上太近)
        输出: "       1       2     -30\n" (固定列宽)
        """
        # 1. 清洗数据：移除方括号（如果有）
        clean_str = line.replace('[', '').replace(']', '')
        
        # 2. 按空格分割（split() 会自动处理多个连续空格）
        parts = clean_str.split()
        if not parts: return ""
        
        # 3. 重组：每个数字强制占用 8 个字符宽度，右对齐
        # 这样配合 Consolas 字体，列就会完美对齐
        formatted = ""
        for part in parts:
            formatted += f"{part:>8}" 
            
        return formatted + "\n"

    def send_uart(self, char, tag="CMD"):
        if self.check_connection():
            try:
                self.ser.write(char.encode('ascii'))
                self.log_msg(f"TX: '{char}' ({tag})")
            except Exception as e:
                self.log_msg(f"TX Err: {e}")

    def log_msg(self, msg, is_rx=False):
        self.txt_log.config(state='normal')
        tag = "RX" if is_rx else "TX"
        color = "#a5d6a7" if is_rx else "#90caf9"
        self.txt_log.tag_config(tag, foreground=color)
        self.txt_log.insert(tk.END, f"[{time.strftime('%H:%M:%S')}] {msg}\n", tag)
        self.txt_log.see(tk.END)
        self.txt_log.config(state='disabled')

    def append_text(self, widget, text):
        widget.config(state='normal')
        widget.insert(tk.END, text)
        widget.see(tk.END)
        widget.config(state='disabled')

    def clear_text(self, widget):
        widget.config(state='normal')
        widget.delete(1.0, tk.END)
        widget.config(state='disabled')

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.combo_port['values'] = ports
        if ports: self.combo_port.current(0)

if __name__ == "__main__":
    root = tk.Tk()
    app = MatrixFPGA_Professional(root)
    root.mainloop()