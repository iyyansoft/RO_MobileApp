const definitions = [
 ['CAT_SYS','systems','RO Systems','purifier.jpg','#0F62FE',[
  ['Domestic RO System 10 L','RO-SYS-10L',5200,6900,9500,'10 L storage; 75 GPD purification'],
  ['Commercial RO System 25 LPH','RO-SYS-25',12500,16500,22000,'25 litres per hour; commercial purification'],
  ['Commercial RO System 50 LPH','RO-SYS-50',18500,24500,32000,'50 litres per hour; stainless steel frame']]],
 ['CAT_MEM','membranes','Membranes','membrane.jpg','#8B5CF6',[
  ['RO Membrane 75 GPD','RO-MEM-75',450,650,950,'75 GPD; domestic RO replacement'],
  ['RO Membrane 100 GPD','RO-MEM-100',650,900,1300,'100 GPD; high rejection membrane'],
  ['RO Membrane 4040','RO-MEM-4040',4800,6500,9000,'4040 size; commercial RO replacement']]],
 ['CAT_FLT','filters','Filters & Cartridges','cat_filter.jpg','#10B981',[
  ['Sediment Filter 10 Inch','RO-FLT-SED',65,100,180,'10 inch; 5 micron sediment filtration'],
  ['Carbon CTO Filter 10 Inch','RO-FLT-CTO',120,180,300,'10 inch; chlorine and odour reduction'],
  ['Inline Carbon Filter','RO-FLT-INLINE',160,240,400,'Inline post-carbon filtration']]],
 ['CAT_PMP','pumps','Booster Pumps','cat_pump.jpg','#D97706',[
  ['RO Booster Pump 75 GPD','RO-PMP-75',850,1200,1800,'24 V DC; 75 GPD systems'],
  ['RO Booster Pump 100 GPD','RO-PMP-100',1100,1550,2200,'24 V DC; 100 GPD systems'],
  ['RO Booster Pump 300 GPD','RO-PMP-300',2500,3400,4800,'Heavy duty; 300 GPD systems']]],
 ['CAT_PIP','pipes','Pipes & Tubing','cat_spares.jpg','#0284C7',[
  ['PE Tubing 1/4 Inch 10 Metres','RO-PIPE-14',100,160,250,'Food grade PE; 1/4 inch; 10 metre roll'],
  ['PE Tubing 3/8 Inch 10 Metres','RO-PIPE-38',160,240,350,'Food grade PE; 3/8 inch; 10 metre roll'],
  ['RO Inlet Pipe Kit','RO-PIPE-KIT',180,280,450,'Inlet tubing with compatible connectors']]],
 ['CAT_SPR','spares','Spare Parts & Valves','cat_spares.jpg','#DB2777',[
  ['RO Solenoid Valve 24 V','RO-SPR-SV',150,240,380,'24 V DC; inlet shut-off valve'],
  ['RO Power Adapter 24 V','RO-SPR-SMPS',220,350,550,'24 V DC power supply for RO systems'],
  ['RO Filter Housing 10 Inch','RO-SPR-HOUSING',180,290,450,'10 inch filter housing with mounting bracket']]],
];
const categories = definitions.map(([id,key_name,title,image_url,icon_color], index) => ({id,key_name,title,image_url,icon_color,badge_text:'WHOLESALE',display_order:index+1}));
const products = definitions.flatMap(([category_id,category,categoryName,img,,items]) => items.map(([name,sku,purchase_price,price,mrp,description], index) => ({
 id:`SAMPLE_${sku.replaceAll('-','_')}`,category_id,category,categoryName,name,sku,brand:'RO Wholesale',purchase_price,purchasePrice:purchase_price,price,mrp,moq:'MOQ: 1 Piece',stock_quantity:category==='systems'?12:100,min_stock:5,badge:index===0?'FEATURED':'',rating:'0',img,desc:description+'. Sample catalog product. Confirm compatibility before installation.',specs:{Specification:description},features:['Wholesale supply','Replacement and installation support'],applications:'Domestic and commercial water purification',status:'active',createdAt:new Date().toISOString(),
})));
module.exports = {categories,products};
