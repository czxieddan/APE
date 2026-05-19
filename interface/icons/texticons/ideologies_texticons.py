import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext
def generate_gfx_content(max_num: int, ext: str) -> str:
    lines = ["spriteTypes = {"]
    for i in range(max_num + 1):
        lines.append("\tspriteType = {")
        lines.append(f'\t\tname = "GFX_IG{i}_texticon"')
        lines.append(f'\t\ttexturefile = "gfx/icons/texticons/ideologies/{i}{ext}"')
        lines.append("\t\tlegacy_lazy_load = no")
        lines.append("\t}")
    lines.append("}")
    return "\n".join(lines)
def on_generate():
    try:
        max_num = int(entry_num.get().strip())
        if max_num < 0:
            raise ValueError
        ext = combo_ext.get()
        content = generate_gfx_content(max_num, ext)
        text_output.delete("1.0", tk.END)
        text_output.insert("1.0", content)
    except ValueError:
        messagebox.showerror("输入错误", "请输入一个非负整数！")
def on_export():
    content = text_output.get("1.0", tk.END).strip()
    if not content:
        messagebox.showwarning("无内容", "请先生成内容后再导出！")
        return
    file_path = filedialog.asksaveasfilename(
        title="保存为 .gfx 文件",
        defaultextension=".gfx",
        filetypes=[(".gfx 文件", "*.gfx")]
    )
    if file_path:
        try:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(content)
            messagebox.showinfo("导出成功", f"文件已保存至：\n{file_path}")
        except Exception as e:
            messagebox.showerror("导出失败", f"保存时出错：{e}")
root = tk.Tk()
root.title("Team APE Ideology Texticons GFX 注册器")
root.geometry("600x600")
root.resizable(False, True)
frame_top = ttk.Frame(root, padding="10")
frame_top.pack(fill="x")
ttk.Label(frame_top, text="最大数字:").grid(row=0, column=0, sticky="e", padx=5, pady=5)
entry_num = ttk.Entry(frame_top, width=15)
entry_num.grid(row=0, column=1, padx=5, pady=5)
entry_num.insert(0, "0")
ttk.Label(frame_top, text="扩展名:").grid(row=0, column=2, sticky="e", padx=5, pady=5)
combo_ext = ttk.Combobox(frame_top, values=[".dds", ".png"], state="readonly", width=10)
combo_ext.grid(row=0, column=3, padx=5, pady=5)
combo_ext.current(0)  
btn_generate = ttk.Button(frame_top, text="生成", command=on_generate)
btn_generate.grid(row=0, column=4, padx=20, pady=5)
btn_export = ttk.Button(frame_top, text="导出", command=on_export)
btn_export.grid(row=0, column=5, padx=10, pady=5)
text_output = scrolledtext.ScrolledText(root, font=("Consolas", 11), wrap="none")
text_output.pack(fill="both", expand=True, padx=10, pady=10)
root.mainloop()
