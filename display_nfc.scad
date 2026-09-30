// MiEspacioParaCelebrar — Display de sobremesa NFC + QR
// Diseño tipo soporte: base independiente + placa inclinada extraíble.
// Pensado para impresión 3D en PLA/PETG.
//
// DIMENSIONES APROXIMADAS
// Base: 100 x 58 x 24 mm
// Placa: 88 x 128 x 3 mm
// Inclinación: 12°
// Etiqueta NFC recomendada: circular 25–30 mm o adhesiva rectangular equivalente.
//
// Para exportar desde OpenSCAD:
//   part="base"  -> STL de la base
//   part="plate" -> STL de la placa
//   part="assembly" -> vista de conjunto (no es necesario imprimirla)

$fn = 64;
part = "assembly";

base_w = 100;
base_d = 58;
base_h = 24;
base_r = 6;

slot_w = 3.8;
slot_depth = 22;
slot_angle = 12;
slot_y = 2;

plate_w = 88;
plate_h = 128;
plate_t = 3.0;
plate_r = 5;

nfc_d = 30;
nfc_depth = 1.5;
nfc_center_z = 82;

qr_w = 52;
qr_h = 52;
qr_depth = 0.9;
qr_center_z = 35;

module rounded_box(w,d,h,r){
    hull(){
        for(x=[-1,1]) for(y=[-1,1])
            translate([x*(w/2-r), y*(d/2-r), 0])
                cylinder(r=r,h=h);
    }
}

module base(){
    difference(){
        translate([0,0,base_h/2])
            rounded_box(base_w,base_d,base_h,base_r);

        // Ranura inclinada para insertar la placa.
        // La ranura atraviesa prácticamente todo el ancho útil de la base.
        translate([0,slot_y,base_h-1])
            rotate([slot_angle,0,0])
                cube([plate_w+4,slot_depth,base_h+8],center=true);

        // Cavidad inferior opcional para colocar peso/lastre.
        translate([0,9,4])
            rounded_box(64,30,6,4);
    }
}

module plate(){
    // Placa frontal independiente, con esquinas redondeadas.
    difference(){
        translate([0,0,plate_h/2])
            rounded_box(plate_w,plate_t,plate_h,plate_r);

        // Alojamiento posterior para una etiqueta NFC circular.
        translate([0,-plate_t/2-0.01,nfc_center_z])
            rotate([90,0,0])
                cylinder(d=nfc_d,h=nfc_depth+0.05);

        // Receso frontal para una tarjeta/adhesivo QR de 52 x 52 mm.
        translate([0,-plate_t/2-0.02,qr_center_z])
            rotate([90,0,0])
                cube([qr_w,qr_depth,qr_h],center=true);
    }
}

module assembly(){
    base();
    // Representación visual aproximada de la placa insertada.
    translate([0,slot_y,base_h-1])
        rotate([slot_angle,0,0])
            translate([0,0,plate_h/2])
                color("white") rounded_box(plate_w,plate_t,plate_h,plate_r);
}

if(part=="base") base();
if(part=="plate") plate();
if(part=="assembly") assembly();
