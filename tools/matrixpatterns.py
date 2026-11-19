import json,sys
def pat(inputs, result, n, rid):
    ins=",".join('{id:"%s"}'%i if i else "{}" for i in (inputs+[None]*9)[:9])
    return '{id:"ae2:crafting_pattern",count:1,components:{"ae2:encoded_crafting_pattern":{inputs:[%s],result:{id:"%s",count:%d},recipeId:"%s",canSubstitute:1b,canSubstituteFluids:0b}}}'%(ins,result,n,rid)
def core(x, pats, block="extendedae:assembler_matrix_pattern", key="pattern", y=73, z=1544):
    items=",".join("{Slot:%d,"%i+p[1:] for i,p in enumerate(pats))
    return "setblock %d %d %d %s{%s:[%s]}"%(x,y,z,block,key,items)
M="mekanism:"
A=[pat([M+"alloy_infused",M+"basic_control_circuit",M+"alloy_infused"],M+"advanced_control_circuit",1,"mekanism:control_circuit/advanced"),
   pat([M+"alloy_reinforced",M+"advanced_control_circuit",M+"alloy_reinforced"],M+"elite_control_circuit",1,"mekanism:control_circuit/elite"),
   pat([M+"alloy_atomic",M+"elite_control_circuit",M+"alloy_atomic"],M+"ultimate_control_circuit",1,"mekanism:control_circuit/ultimate")]
g="minecraft:glass"; d="ae2:certus_quartz_dust"
B=[pat([g,g,g,d,d,d,g,g,g],"ae2:quartz_fiber",3,"ae2:network/parts/quartz_fiber_part"),
   pat(["ae2:quartz_fiber","ae2:fluix_crystal","ae2:fluix_crystal"],"ae2:fluix_glass_cable",4,"ae2:network/cables/glass_fluix"),
   pat(["ae2:quartz_glass","minecraft:glowstone_dust","ae2:quartz_glass","minecraft:glowstone_dust","ae2:certus_quartz_crystal","minecraft:glowstone_dust","minecraft:iron_ingot","minecraft:copper_ingot","minecraft:iron_ingot"],"ae2:blank_pattern",2,"ae2:network/crafting/patterns_blank")]
s="minecraft:stone"; i="minecraft:iron_ingot"; p="minecraft:oak_planks"
C=[pat([s,s,s,s,"minecraft:redstone",s,s,"minecraft:glass_pane",s],"computercraft:computer_normal",1,"computercraft:computer_normal"),
   pat([i,i,i,i,"computercraft:computer_normal",i,i,"minecraft:chest",i],"computercraft:turtle_normal",1,"computercraft:turtle_normal"),
   pat([p,p,p,p,None,p,p,p,p],"minecraft:chest",1,"minecraft:chest")]
# second row of pattern cores (y 4 of the matrix, where the speed cores stood)
w="minecraft:white_wool"; gc="ae2:fluix_glass_cable"; cc="ae2:fluix_covered_cable"; rd="minecraft:redstone"; gl="minecraft:glowstone_dust"
D=[pat([d,g,d,g,d,g,d,g,d],"ae2:quartz_glass",4,"ae2:decorative/quartz_glass"),
   pat([w,gc],"ae2:fluix_covered_cable",1,"ae2:network/cables/covered_fluix"),
   pat([cc,rd,gl],"ae2:fluix_smart_cable",1,"ae2:network/cables/smart_fluix")]
E=[pat([None,s,None,s,rd,s,None,s,None],"computercraft:cable",6,"computercraft:cable"),
   pat([s,s,s,s,rd,s,s,s,s],"computercraft:wired_modem",1,"computercraft:wired_modem"),
   pat([g,g,g,g,g,g],"minecraft:glass_pane",16,"minecraft:glass_pane")]
st="alltheores:steel_ingot"; os_="alltheores:osmium_ingot"; od="alltheores:osmium_dust"; ai=M+"alloy_infused"
F=[pat([st,g,st,g,os_,g,st,g,st],M+"steel_casing",1,"mekanism:steel_casing"),
   pat([None,g,None,ai,od,ai,None,g,None],M+"upgrade_speed",1,"mekanism:upgrade/speed"),
   pat([cc,cc,cc,cc],"ae2:fluix_covered_dense_cable",1,"ae2:network/cables/dense_covered_fluix")]
out=[core(-4418,A),core(-4417,B),core(-4416,C),core(-4418,D,y=75),core(-4417,E,y=75),core(-4416,F,y=75)]
if __name__=="__main__":
    import os
    for o in out: print(len(o.encode()))
    json.dump(out,open(os.path.join(os.environ.get("TMPDIR","/tmp"),"matrix_cmds.json"),"w"))
