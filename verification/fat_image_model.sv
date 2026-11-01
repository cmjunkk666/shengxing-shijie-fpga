// Sparse independent FAT32 image model. No image content generated from DUT signals.
// mode: 0 MBR, 1 superfloppy/missing PIC3, 2 bad BPB, 3 early FAT EOF,
// 4 root loop, 5 file loop, 6 bad width, 7 transport failure, 8 short file, 9 offset overflow.
module fat_image_model #(parameter GAP=3)(
 input wire clk,rst,req,input wire [31:0] lba,input wire ready,input integer mode,
 output reg busy,valid,output reg [7:0] data,output reg [8:0] index,
 output reg done,output reg [7:0] error,output integer requests
);
 localparam FATLEN=550,SPC=2,RESERVED=32,TOTAL=141132;
 reg [31:0] addr;integer delay_count;reg [1:0] state;integer n;
 function automatic [7:0] lebyte(input reg [31:0] value,input integer offset);
  lebyte=(value>>(8*offset))&255;
 endfunction
 function automatic [7:0] image(input reg [31:0] a,input integer b);
  integer vol,base,cl,off,idx,cid,part,ent,field,scene,first,k,pos,pix;
  reg [31:0] value;reg [7:0] r;
  begin
   vol=mode==1?0:2048;base=vol+RESERVED+2*FATLEN;r=0;
   if(a==0 && vol!=0) begin
    if(b==510)r=8'h55;if(b==511)r=8'haa;
    // FAT32 is deliberately the second partition.
    if(b==466)r=8'h0c;
    if(b>=470 && b<474)r=lebyte(2048,b-470);
    if(b>=474 && b<478)r=lebyte(TOTAL,b-474);
   end else if(a==vol) begin
    case(b)
     11:r=0;12:r=mode==2?4:2;13:r=SPC;14:r=RESERVED;16:r=2;
     510:r=8'h55;511:r=8'haa;default:;
    endcase
    if(b>=32 && b<36)r=lebyte(TOTAL,b-32);
    if(b>=36 && b<40)r=lebyte(FATLEN,b-36);
    if(b>=44 && b<48)r=lebyte(5,b-44);
   end else if(a>=vol+RESERVED && a<vol+RESERVED+FATLEN) begin
    cid=(a-vol-RESERVED)*128+b/4;value=32'h0fffffff;
    if(cid==5)value=9;
    if(cid==9 && mode==4)value=5;
    for(scene=0;scene<4;scene=scene+1) begin
     first=20+scene*10000;
     if(cid>=first && cid<=first+1800 && (cid-first)%2==0) begin
      value=cid==first+1800?32'h0fffffff:cid+2;
      if(mode==3 && scene==0 && cid==first)value=32'h0fffffff;
      if(mode==5 && scene==0 && cid==first+1800)value=first;
     end
    end
    r=lebyte(value,b%4);
   end else if(a>=base) begin
    cl=(a-base)/2+2;off=(a-base)%2;ent=b/32;field=b%32;
    if(cl==5 || cl==9) begin
     r=field==0?8'he5:0;scene=-1;
     if(mode!=4) begin
      if(cl==5 && off==1 && ent==3)scene=0;
      if(cl==9 && off==0 && ent<3)scene=ent+1;
      if(cl==9 && off==0 && ent==3 && field==0)r=0;
     end
     if(scene>=0 && !(mode==1 && scene==2)) begin
      case(field)
       0:r="P";1:r="I";2:r="C";3:r=8'h31+scene;
       4,5,6,7:r=" ";8:r="B";9:r="M";10:r="P";
       11:r=scene==3?8'h03:8'h20;default:r=0;
      endcase
      first=20+scene*10000;
      if(field==20)r=lebyte(first,2);if(field==21)r=lebyte(first,3);
      if(field==26)r=lebyte(first,0);if(field==27)r=lebyte(first,1);
      if(field>=28)r=lebyte(mode==8 && scene==0?900000:921654,field-28);
     end
    end else for(scene=0;scene<4;scene=scene+1) begin
     first=20+scene*10000;
     if(cl>=first && cl<=first+1800 && (cl-first)%2==0) begin
      k=(cl-first)/2;pos=k*1024+off*512+b;
      if(pos<54) begin
       case(pos)
        0:r="B";1:r="M";26:r=1;28:r=24;default:r=0;
       endcase
       if(pos>=2 && pos<6)r=lebyte(921654,pos-2);
       if(pos>=10 && pos<14)r=lebyte(mode==9?32'hfffffff0:54,pos-10);
       if(pos>=14 && pos<18)r=lebyte(40,pos-14);
       if(pos>=18 && pos<22)r=lebyte(mode==6 && scene==0?641:640,pos-18);
       if(pos>=22 && pos<26)r=lebyte(480,pos-22);
       if(pos>=34 && pos<38)r=lebyte(921600,pos-34);
      end else begin
       pix=(pos-54)/3;
       case((pos-54)%3)
        0:r=pix%640;1:r=pix/640;2:r=scene*40+17;
       endcase
      end
     end
    end
   end
   image=r;
  end
 endfunction
 always @(posedge clk) begin
  if(rst) begin busy<=0;valid<=0;done<=0;error<=0;index<=0;data<=0;state<=0;requests<=0;delay_count<=0;addr<=0;end
  else begin
   done<=0;
   case(state)
    0:if(req) begin addr<=lba;busy<=1;error<=0;requests<=requests+1;delay_count<=GAP;state<=1;end
    1:if(delay_count>0)delay_count<=delay_count-1;else begin
      if(mode==7 && addr==((2048+32+1100)+(20-2)*2+1))begin error<=8'h05;state<=3;end
      else begin valid<=1;index<=0;data<=image(addr,0);state<=2;end
     end
    2:if(ready)begin
      if(index==511)begin valid<=0;state<=3;end
      else begin index<=index+1'b1;data<=image(addr,index+1);end
     end
    3:begin done<=1;busy<=0;state<=0;end
   endcase
  end
 end
endmodule
