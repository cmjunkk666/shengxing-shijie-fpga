"""Isolated controller/UI tests. SD and frame-memory completion are modeled.

Use --modelsim-bin for a different ModelSim installation. Outputs stay in verification/out.
"""
from pathlib import Path
import argparse, subprocess, re, json

parser=argparse.ArgumentParser()
parser.add_argument('--modelsim-bin',default=r'C:\intelFPGA_pro\20.4\modelsim_ase\win32aloem')
args=parser.parse_args()
here=Path(__file__).resolve().parent
hdl=here.parent/'src/user_source/hdl_source'
out=here/'out'
out.mkdir(exist_ok=True)

# Same interfaces as the actual source modules, with controllable timing in simulation.
bmp=(hdl/'SD/bmp_read.v').read_text(encoding='utf-8-sig').split('localparam ST_IDLE')[0]
bmp += '''
integer model_count=4;
reg allow_complete=0;
reg model_ready=1;
integer scan_index=0, mode=0, age=0;
assign ready=model_ready;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        load_error<=0;mode<=0; model_ready<=1;scan_done<=0;scan_found_valid<=0;
        scan_found_sector<=0;scan_found_total<=0;scan_index<=0;age<=0;
        state_code<=0;write_req<=0;sd_sec_read<=0;sd_sec_read_addr<=0;
        bmp_data_wr_en<=0;bmp_data<=0;
    end else begin
        scan_found_valid<=0;
        if(scan_start) begin mode<=1;model_ready<=0;scan_done<=0;scan_index<=0;end
        else if(load_start) begin mode<=2;model_ready<=0;age<=0;state_code<=4;end
        else if(mode==1) begin
            if(scan_index<model_count) begin
                scan_found_valid<=1;scan_found_sector<=1000+scan_index*2000;
                scan_index<=scan_index+1;scan_found_total<=scan_index+1;
            end else begin mode<=0;model_ready<=1;scan_done<=1;state_code<=1;end
        end else if(mode==2) begin
            age<=age+1;
            if(age>=8 && allow_complete) begin mode<=0;model_ready<=1;state_code<=1;end
        end
    end
end
endmodule
'''
sd=(hdl/'SD/sd_card_top.v').read_text(encoding='utf-8-sig').split('wire[15:0]')[0]
sd+='''
reg model_initialized=1;
assign sd_init_done=model_initialized;
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;
assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
'''
(out/'media_stubs.v').write_text(bmp+sd,encoding='utf-8')
binpath=Path(args.modelsim_bin)
commands=[
 [str(binpath/'vlib.exe'),'work'],
 [str(binpath/'vlog.exe'),'-sv','-work','work',str(hdl/'key_events.v'),str(hdl/'player_status_display.v'),str(hdl/'SD/sd_card_bmp.v'),str(out/'media_stubs.v'),str(here/'tb_key_events.sv'),str(here/'tb_player_control.sv')]
]
results=[]
for tb in ['tb_key_events','tb_player_control']:
    do=out/(tb+'.do')
    do.write_text('onerror {quit -code 1 -force}\nonbreak {quit -code 1 -force}\nrun -all\nquit -code 0 -force\n',encoding='ascii')
    commands.append([str(binpath/'vsim.exe'),'-c','-onfinish','exit','-voptargs=+acc','work.'+tb,'-do',str(do)])
for idx,command in enumerate(commands):
    proc=subprocess.run(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    output=proc.stdout.decode('utf-8',errors='replace')
    (out/f'{idx:02d}.log').write_text(output,encoding='utf-8')
    print(output)
    ok=proc.returncode==0 and not re.search(r'\*\* (?:Error|Fatal)',output)
    if idx>=2: ok=ok and ('PASS tb_' in output)
    results.append({'command':command,'returncode':proc.returncode,'passed':ok})
    if not ok:
        (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        raise SystemExit(1)
(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('All ModelSim controller/UI tests passed.')
