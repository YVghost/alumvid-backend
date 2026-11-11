package com.alumvid.pedidos;

import java.math.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** Lectura sin efectos laterales. La confirmacion vuelve a planificar con productos bloqueados. */
@Component
class AvailabilityPlanner {
    record Allocation(int position,UUID productId,UUID pieceId,BigDecimal extent,BigDecimal waste,BigDecimal quantity) {}
    record Plan(List<Map<String,Object>> lines,List<Allocation> allocations,boolean available) {}
    static Map<String,Object> map(Object... args) {Map<String,Object> m=new LinkedHashMap<>();for(int i=0;i<args.length;i+=2)m.put((String)args[i],args[i+1]);return m;}
    static BigDecimal decimal(Object x) {return x==null?BigDecimal.ZERO:new BigDecimal(x.toString());}
    static BigDecimal units(BigDecimal measure,BigDecimal reference) {return measure.divide(reference,12,RoundingMode.HALF_UP);}
    static UUID uuid(Object x) {return UUID.fromString(x.toString());}
    private final JdbcTemplate db;
    AvailabilityPlanner(JdbcTemplate db) {this.db=db;}
    Map<String,Object> product(UUID id) {return db.queryForList("SELECT p.*,f.kind,f.full_length_m,f.full_width_cm,f.full_height_cm,f.unallocated_measure FROM inventario.product p LEFT JOIN retazos.material_format f ON f.product_id=p.id WHERE p.id=?",id).stream().findFirst().orElseThrow(()->new PedidosError(404,"Producto no encontrado: "+id));}
    static class StockPiece {
        UUID id;BigDecimal remaining;BigDecimal full;String location;
        StockPiece(Map<String,Object> r,boolean aluminum,BigDecimal full) {id=uuid(r.get("id"));remaining=decimal(r.get(aluminum?"length_m":"width_cm"));this.full=full;location=(String)r.get("location");}
    }
    Plan plan(List<PedidosApi.Line> inputs) {
        Map<UUID,Map<String,Object>> products=new HashMap<>();
        Map<UUID,BigDecimal> balances=new HashMap<>();Map<UUID,List<StockPiece>> pieces=new HashMap<>();
        List<Map<String,Object>> lines=new ArrayList<>();List<Allocation> allocations=new ArrayList<>();boolean all=true;
        int position=0;
        for(var line:inputs) {
            var p=products.computeIfAbsent(line.productId(),this::product);boolean managed=Boolean.TRUE.equals(p.get("pieces_managed"));
            BigDecimal qty=line.quantity(),reserved=BigDecimal.ZERO,extent=null;
            BigDecimal waste=line.wasteExtent()==null?BigDecimal.ZERO:line.wasteExtent();
            List<Map<String,Object>> suggestions=new ArrayList<>();
            if(managed) {
                if(qty.stripTrailingZeros().scale()>0||qty.compareTo(BigDecimal.valueOf(200))>0)throw new PedidosError(400,"Las piezas requieren cantidad entera entre 1 y 200");
                boolean aluminum="ALUMINIO".equals(p.get("kind"));
                BigDecimal full=decimal(p.get(aluminum?"full_length_m":"full_width_cm"));
                if(full.signum()<=0)throw new PedidosError(409,"Falta configurar las medidas completas en Retazos");
                if(aluminum) {
                    if(line.widthCm()!=null||line.heightCm()!=null)throw new PedidosError(400,"Aluminio utiliza longitud en metros");
                    extent=line.lengthM()==null?full:line.lengthM();
                } else {
                    if(line.lengthM()!=null)throw new PedidosError(400,"Vidrio utiliza ancho y alto en centimetros");
                    if((line.widthCm()==null)!=(line.heightCm()==null))throw new PedidosError(400,"Indica ancho y alto del vidrio");
                    if(line.heightCm()!=null&&line.heightCm().compareTo(decimal(p.get("full_height_cm")))!=0)throw new PedidosError(400,"El vidrio solo se corta por ancho: el alto debe coincidir con la plancha completa");
                    extent=line.widthCm()==null?full:line.widthCm();
                }
                if(extent.add(waste).compareTo(full)>0)throw new PedidosError(400,"Medida y merma superan la unidad completa");
                var pool=pieces.computeIfAbsent(line.productId(),id->db.queryForList("SELECT p.* FROM retazos.piece p WHERE p.product_id=? AND p.state='DISPONIBLE' AND NOT EXISTS(SELECT 1 FROM inventario.stock_reservation r WHERE r.piece_id=p.id AND r.state='ACTIVA') ORDER BY p.created_at,p.id",id).stream().map(r->new StockPiece(r,aluminum,full)).toList());
                if(Boolean.TRUE.equals(p.get("active"))) {
                    BigDecimal required=extent.add(waste);
                    for(int i=0;i<qty.intValueExact();i++) {
                        var best=pool.stream().filter(x->x.remaining.compareTo(required)>=0)
                            .min(Comparator.<StockPiece,Boolean>comparing(x->x.remaining.compareTo(x.full)==0).thenComparing(x->x.remaining).thenComparing(x->x.id)).orElse(null);
                        if(best==null)break;
                        suggestions.add(map("pieceId",best.id,"sourceExtent",best.remaining,"useExtent",extent,"wasteExtent",waste,"sourceType",best.remaining.compareTo(full)<0?"RETAZO":"COMPLETO","location",best.location));
                        allocations.add(new Allocation(position,line.productId(),best.id,extent,waste,BigDecimal.ONE));
                        best.remaining=best.remaining.subtract(required);reserved=reserved.add(BigDecimal.ONE);
                    }
                }
            } else {
                if(line.lengthM()!=null||line.widthCm()!=null||line.heightCm()!=null||waste.signum()!=0)throw new PedidosError(400,"Configura este material en Retazos antes de solicitar medidas exactas");
                var balance=balances.computeIfAbsent(line.productId(),id->decimal(p.get("stock")).subtract(db.queryForObject("SELECT COALESCE(SUM(quantity),0) FROM inventario.stock_reservation WHERE product_id=? AND state='ACTIVA'",BigDecimal.class,id)).max(BigDecimal.ZERO));
                if(Boolean.TRUE.equals(p.get("active")))reserved=qty.min(balance);
                balances.put(line.productId(),balance.subtract(reserved));
                if(reserved.signum()>0)allocations.add(new Allocation(position,line.productId(),null,null,BigDecimal.ZERO,reserved));
            }
            BigDecimal missing=qty.subtract(reserved);if(missing.signum()>0)all=false;
            lines.add(map("position",position,"productId",line.productId(),"code",p.get("code"),"name",p.get("name"),"unit",p.get("unit"),"requestedQuantity",qty,"availableQuantity",reserved,"missingQuantity",missing,
                "state",missing.signum()==0?"RESERVADO":reserved.signum()>0?"PARCIAL":"PENDIENTE","suggestions",suggestions,
                "notice",!Boolean.TRUE.equals(p.get("active"))?"Producto inactivo":managed&&decimal(p.get("unallocated_measure")).signum()>0?"Existe stock sin medidas verificadas: detallar en Retazos antes de prometer su disponibilidad":""));
            position++;
        }
        return new Plan(lines,allocations,all);
    }
}
