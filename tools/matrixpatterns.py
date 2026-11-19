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
out=[core(-4418,A),core(-4417,B),core(-4416,C)]
for o in out: print(len(o.encode()))
json.dump(out,open("cmds.json","w"))
