/**
 * renovationCatalog.js — Catálogo completo de partidas de reforma
 * Precios orientativos mercado español 2024 (mano de obra + materiales)
 * Zerbitecni · mi-render
 */

export const RENOVATION_CATALOG = {

  // ── PINTURA ─────────────────────────────────────────────────────────────────
  pintura: {
    label: 'Pintura',
    icon: '🎨',
    color: '#f0a500',
    items: [
      { description: 'Pintura plástica lisa paredes (2 manos)',           unit: 'm²', unitPrice: 8,   category: 'pintura' },
      { description: 'Pintura plástica lisa techo (2 manos)',             unit: 'm²', unitPrice: 9,   category: 'pintura' },
      { description: 'Pintura plástica gotelé fino paredes',              unit: 'm²', unitPrice: 7,   category: 'pintura' },
      { description: 'Pintura plástica gotelé techo',                     unit: 'm²', unitPrice: 7.5, category: 'pintura' },
      { description: 'Imprimación selladora paredes',                     unit: 'm²', unitPrice: 3.5, category: 'pintura' },
      { description: 'Preparación y lijado de superficies',               unit: 'm²', unitPrice: 4.5, category: 'pintura' },
      { description: 'Picado y saneado de gotelé existente',              unit: 'm²', unitPrice: 6,   category: 'pintura' },
      { description: 'Enlucido de paredes (acabado liso)',                unit: 'm²', unitPrice: 12,  category: 'pintura' },
      { description: 'Pintura exterior fachada (2 manos)',                unit: 'm²', unitPrice: 11,  category: 'pintura' },
      { description: 'Pintura esmalte puertas y ventanas',                unit: 'ud', unitPrice: 65,  category: 'pintura' },
      { description: 'Pintura esmalte radiadores',                        unit: 'ud', unitPrice: 35,  category: 'pintura' },
      { description: 'Pintura epoxi suelo garaje',                        unit: 'm²', unitPrice: 18,  category: 'pintura' },
      { description: 'Pintura antihumedad paredes',                       unit: 'm²', unitPrice: 14,  category: 'pintura' },
      { description: 'Masilla y relleno de grietas/agujeros',             unit: 'ud', unitPrice: 8,   category: 'pintura' },
      { description: 'Revestimiento decorativo estuco veneciano',         unit: 'm²', unitPrice: 45,  category: 'pintura' },
    ],
  },

  // ── TECHOS ──────────────────────────────────────────────────────────────────
  techos: {
    label: 'Techos',
    icon: '🏠',
    color: '#a78bfa',
    items: [
      { description: 'Falso techo pladur liso (estructura + placa)',      unit: 'm²', unitPrice: 28,  category: 'techos' },
      { description: 'Falso techo pladur con aislante térmico/acústico', unit: 'm²', unitPrice: 38,  category: 'techos' },
      { description: 'Falso techo pladur con instalación eléctrica',     unit: 'm²', unitPrice: 45,  category: 'techos' },
      { description: 'Falso techo pladur curvo/diseño',                  unit: 'm²', unitPrice: 55,  category: 'techos' },
      { description: 'Falso techo escayola liso',                        unit: 'm²', unitPrice: 22,  category: 'techos' },
      { description: 'Moldura de escayola perimetral',                   unit: 'ml', unitPrice: 8,   category: 'techos' },
      { description: 'Roseta decorativa escayola',                       unit: 'ud', unitPrice: 35,  category: 'techos' },
      { description: 'Vigas decorativas madera maciza',                  unit: 'ml', unitPrice: 55,  category: 'techos' },
      { description: 'Techo de madera machihembrado',                    unit: 'm²', unitPrice: 65,  category: 'techos' },
      { description: 'Desmontaje techo existente',                       unit: 'm²', unitPrice: 8,   category: 'techos' },
      { description: 'Aislante proyectado techo (poliuretano)',          unit: 'm²', unitPrice: 25,  category: 'techos' },
      { description: 'Spot embutido LED (instalación incluida)',          unit: 'ud', unitPrice: 45,  category: 'techos' },
      { description: 'Tira LED perimetral techo',                        unit: 'ml', unitPrice: 18,  category: 'techos' },
    ],
  },

  // ── BAÑOS ───────────────────────────────────────────────────────────────────
  banos: {
    label: 'Baños',
    icon: '🚿',
    color: '#2dd4bf',
    items: [
      { description: 'Reforma completa baño (sin materiales)',            unit: 'ud', unitPrice: 1800, category: 'banos' },
      { description: 'Alicatado paredes baño (azulejo hasta 40€/m²)',    unit: 'm²', unitPrice: 38,   category: 'banos' },
      { description: 'Solado suelo baño (porcelánico hasta 40€/m²)',     unit: 'm²', unitPrice: 35,   category: 'banos' },
      { description: 'Inodoro con instalación (gama media)',              unit: 'ud', unitPrice: 320,  category: 'banos' },
      { description: 'Lavabo con pedestal e instalación',                 unit: 'ud', unitPrice: 280,  category: 'banos' },
      { description: 'Mueble lavabo suspendido 80cm + instalación',      unit: 'ud', unitPrice: 550,  category: 'banos' },
      { description: 'Bañera acrílica 150cm + instalación',              unit: 'ud', unitPrice: 420,  category: 'banos' },
      { description: 'Plato de ducha 80×80cm + instalación',             unit: 'ud', unitPrice: 380,  category: 'banos' },
      { description: 'Mampara de ducha 80cm + instalación',              unit: 'ud', unitPrice: 450,  category: 'banos' },
      { description: 'Grifería monomando lavabo (gama media)',            unit: 'ud', unitPrice: 120,  category: 'banos' },
      { description: 'Grifería termost. ducha/bañera (gama media)',      unit: 'ud', unitPrice: 280,  category: 'banos' },
      { description: 'Radiador toallero eléctrico + instalación',        unit: 'ud', unitPrice: 220,  category: 'banos' },
      { description: 'Extractor de baño + instalación',                  unit: 'ud', unitPrice: 95,   category: 'banos' },
      { description: 'Espejo retroiluminado LED',                        unit: 'ud', unitPrice: 180,  category: 'banos' },
      { description: 'Cambio de bañera por plato de ducha',              unit: 'ud', unitPrice: 850,  category: 'banos' },
      { description: 'Impermeabilización plato ducha (tela asfáltica)',  unit: 'ud', unitPrice: 120,  category: 'banos' },
      { description: 'Rejiband y mortero nivelación suelo húmedo',       unit: 'm²', unitPrice: 18,   category: 'banos' },
    ],
  },

  // ── COCINAS ─────────────────────────────────────────────────────────────────
  cocinas: {
    label: 'Cocinas',
    icon: '🍳',
    color: '#ff6b35',
    items: [
      { description: 'Reforma integral cocina (sin muebles ni materiales)', unit: 'ud', unitPrice: 2200, category: 'cocinas' },
      { description: 'Alicatado cocina (azulejo hasta 40€/m²)',           unit: 'm²', unitPrice: 38,   category: 'cocinas' },
      { description: 'Módulo alto cocina 60cm (instalación)',              unit: 'ud', unitPrice: 180,  category: 'cocinas' },
      { description: 'Módulo bajo cocina 60cm (instalación)',              unit: 'ud', unitPrice: 200,  category: 'cocinas' },
      { description: 'Encimera granito natural 60cm (ml)',                unit: 'ml', unitPrice: 180,  category: 'cocinas' },
      { description: 'Encimera Silestone/cuarzo 60cm (ml)',               unit: 'ml', unitPrice: 250,  category: 'cocinas' },
      { description: 'Encimera acero inoxidable 60cm (ml)',               unit: 'ml', unitPrice: 220,  category: 'cocinas' },
      { description: 'Encimera compacto (ML) Formica/laminado',          unit: 'ml', unitPrice: 120,  category: 'cocinas' },
      { description: 'Fregadero acero inox. 2 senos + instalación',      unit: 'ud', unitPrice: 280,  category: 'cocinas' },
      { description: 'Grifería monomando cocina + instalación',          unit: 'ud', unitPrice: 130,  category: 'cocinas' },
      { description: 'Campana extractora 60cm + instalación',            unit: 'ud', unitPrice: 320,  category: 'cocinas' },
      { description: 'Horno empotrable + instalación eléctrica',         unit: 'ud', unitPrice: 380,  category: 'cocinas' },
      { description: 'Placa vitrocerámica/inducción 60cm + instalación', unit: 'ud', unitPrice: 420,  category: 'cocinas' },
      { description: 'Lavavajillas empotrable + instalación',            unit: 'ud', unitPrice: 350,  category: 'cocinas' },
      { description: 'Frigo americano + instalación',                    unit: 'ud', unitPrice: 950,  category: 'cocinas' },
      { description: 'Zócalo rodapié cocina (ml)',                       unit: 'ml', unitPrice: 12,   category: 'cocinas' },
    ],
  },

  // ── SUELOS ──────────────────────────────────────────────────────────────────
  suelos: {
    label: 'Suelos',
    icon: '🪵',
    color: '#d97706',
    items: [
      { description: 'Tarima flotante laminada 8mm (colocación)',        unit: 'm²', unitPrice: 22,  category: 'suelos' },
      { description: 'Tarima flotante madera natural (colocación)',      unit: 'm²', unitPrice: 38,  category: 'suelos' },
      { description: 'Parquet macizo entarimado (colocación)',           unit: 'm²', unitPrice: 55,  category: 'suelos' },
      { description: 'Cerámica/porcelánico hasta 60×60cm',              unit: 'm²', unitPrice: 32,  category: 'suelos' },
      { description: 'Porcelánico gran formato 80×80cm+',               unit: 'm²', unitPrice: 45,  category: 'suelos' },
      { description: 'Microcemento suelo (2 capas + sellador)',          unit: 'm²', unitPrice: 65,  category: 'suelos' },
      { description: 'Mármol o piedra natural (colocación)',             unit: 'm²', unitPrice: 60,  category: 'suelos' },
      { description: 'Vinilo/SPC clic (colocación)',                     unit: 'm²', unitPrice: 18,  category: 'suelos' },
      { description: 'Moqueta (colocación)',                             unit: 'm²', unitPrice: 15,  category: 'suelos' },
      { description: 'Rodapié madera 70mm (colocación)',                unit: 'ml', unitPrice: 9,   category: 'suelos' },
      { description: 'Rodapié porcelánico (colocación)',                 unit: 'ml', unitPrice: 11,  category: 'suelos' },
      { description: 'Nivelación de suelo (autonivelante)',              unit: 'm²', unitPrice: 12,  category: 'suelos' },
      { description: 'Levantado de solado existente',                    unit: 'm²', unitPrice: 8,   category: 'suelos' },
      { description: 'Barnizado/lijado parquet existente',               unit: 'm²', unitPrice: 18,  category: 'suelos' },
    ],
  },

  // ── ELECTRICIDAD ────────────────────────────────────────────────────────────
  electricidad: {
    label: 'Electricidad',
    icon: '⚡',
    color: '#fbbf24',
    items: [
      { description: 'Cuadro eléctrico ICP + 8 circuitos',              unit: 'ud', unitPrice: 650,  category: 'electricidad' },
      { description: 'Circuito eléctrico completo (cable + canaleta)',   unit: 'ud', unitPrice: 180,  category: 'electricidad' },
      { description: 'Punto de luz (interruptor + luminaria base)',      unit: 'ud', unitPrice: 55,   category: 'electricidad' },
      { description: 'Enchufe empotrado con toma tierra',                unit: 'ud', unitPrice: 38,   category: 'electricidad' },
      { description: 'Interruptor/conmutador empotrado',                 unit: 'ud', unitPrice: 42,   category: 'electricidad' },
      { description: 'Punto de luz aplique pared',                      unit: 'ud', unitPrice: 48,   category: 'electricidad' },
      { description: 'Spot empotrable LED techo',                       unit: 'ud', unitPrice: 45,   category: 'electricidad' },
      { description: 'Toma corriente TV/SAT',                           unit: 'ud', unitPrice: 55,   category: 'electricidad' },
      { description: 'Toma corriente RJ45 (red datos)',                  unit: 'ud', unitPrice: 58,   category: 'electricidad' },
      { description: 'Detector de humo homologado + instalación',        unit: 'ud', unitPrice: 65,   category: 'electricidad' },
      { description: 'Domótica — persiana motorizada (por punto)',       unit: 'ud', unitPrice: 180,  category: 'electricidad' },
      { description: 'Timbre/video portero + instalación',               unit: 'ud', unitPrice: 320,  category: 'electricidad' },
      { description: 'Instalación eléctrica completa piso 80m²',        unit: 'ud', unitPrice: 3200, category: 'electricidad' },
      { description: 'Cargador vehículo eléctrico (wallbox) + instalación', unit: 'ud', unitPrice: 850, category: 'electricidad' },
    ],
  },

  // ── FONTANERÍA ──────────────────────────────────────────────────────────────
  fontaneria: {
    label: 'Fontanería',
    icon: '🔧',
    color: '#38bdf8',
    items: [
      { description: 'Calentador eléctrico 80L + instalación',           unit: 'ud', unitPrice: 450,  category: 'fontaneria' },
      { description: 'Caldera gas condensación 24kW + instalación',      unit: 'ud', unitPrice: 2200, category: 'fontaneria' },
      { description: 'Termo eléctrico 50L + instalación',                unit: 'ud', unitPrice: 320,  category: 'fontaneria' },
      { description: 'Tubería de cobre (agua fría/caliente) por ml',    unit: 'ml', unitPrice: 22,   category: 'fontaneria' },
      { description: 'Tubería multicapa/PEX por ml',                     unit: 'ml', unitPrice: 18,   category: 'fontaneria' },
      { description: 'Bajante PVC 110mm por ml',                         unit: 'ml', unitPrice: 28,   category: 'fontaneria' },
      { description: 'Sustitución bajante completa',                     unit: 'ud', unitPrice: 380,  category: 'fontaneria' },
      { description: 'Punto de agua (conexión toma agua y desagüe)',     unit: 'ud', unitPrice: 120,  category: 'fontaneria' },
      { description: 'Radiador aluminio 6 elementos + instalación',      unit: 'ud', unitPrice: 280,  category: 'fontaneria' },
      { description: 'Suelo radiante eléctrico (cable calef.)',           unit: 'm²', unitPrice: 55,   category: 'fontaneria' },
      { description: 'Suelo radiante agua (instalación)',                 unit: 'm²', unitPrice: 45,   category: 'fontaneria' },
      { description: 'Instalación fontanería completa piso 80m²',        unit: 'ud', unitPrice: 2800, category: 'fontaneria' },
      { description: 'Desatascos/limpieza tuberías',                     unit: 'ud', unitPrice: 150,  category: 'fontaneria' },
    ],
  },

  // ── AIRE ACONDICIONADO ──────────────────────────────────────────────────────
  climatizacion: {
    label: 'Climatización',
    icon: '❄️',
    color: '#7dd3fc',
    items: [
      { description: 'Aire acondicionado split 1×1 2500 frigorías',      unit: 'ud', unitPrice: 850,  category: 'climatizacion' },
      { description: 'Aire acondicionado split 1×1 3500 frigorías',      unit: 'ud', unitPrice: 1100, category: 'climatizacion' },
      { description: 'Aire acondicionado split 1×1 5000 frigorías',      unit: 'ud', unitPrice: 1400, category: 'climatizacion' },
      { description: 'Multi-split 2×1 (unid. exterior + 2 interiores)',  unit: 'ud', unitPrice: 2200, category: 'climatizacion' },
      { description: 'Multi-split 3×1 (unid. exterior + 3 interiores)',  unit: 'ud', unitPrice: 3200, category: 'climatizacion' },
      { description: 'Multi-split 4×1 (unid. exterior + 4 interiores)',  unit: 'ud', unitPrice: 4200, category: 'climatizacion' },
      { description: 'Cassette de techo 1×1 + instalación',             unit: 'ud', unitPrice: 1800, category: 'climatizacion' },
      { description: 'Conducto empotrado + rejillas (por estancia)',     unit: 'ud', unitPrice: 1200, category: 'climatizacion' },
      { description: 'Sistema conductos vivienda completa (80m²)',       unit: 'ud', unitPrice: 6500, category: 'climatizacion' },
      { description: 'Recuperador de calor (VMC doble flujo)',            unit: 'ud', unitPrice: 2800, category: 'climatizacion' },
      { description: 'Bomba de calor aerotermia 8kW',                    unit: 'ud', unitPrice: 5500, category: 'climatizacion' },
      { description: 'Mantenimiento anual aire acondicionado',           unit: 'ud', unitPrice: 120,  category: 'climatizacion' },
      { description: 'Carga de gas refrigerante',                        unit: 'ud', unitPrice: 180,  category: 'climatizacion' },
    ],
  },

  // ── CARPINTERÍA ─────────────────────────────────────────────────────────────
  carpinteria: {
    label: 'Carpintería',
    icon: '🚪',
    color: '#86efac',
    items: [
      { description: 'Puerta interior maciza 70cm + marcos + instalación', unit: 'ud', unitPrice: 380, category: 'carpinteria' },
      { description: 'Puerta interior hueca 70cm + marcos + instalación', unit: 'ud', unitPrice: 280, category: 'carpinteria' },
      { description: 'Puerta corredera interior + instalación',           unit: 'ud', unitPrice: 420, category: 'carpinteria' },
      { description: 'Puerta blindada entrada + instalación',             unit: 'ud', unitPrice: 1200, category: 'carpinteria' },
      { description: 'Armario empotrado a medida 2 puertas (2m alto)',   unit: 'ud', unitPrice: 850,  category: 'carpinteria' },
      { description: 'Armario empotrado a medida 3 puertas (2m alto)',   unit: 'ud', unitPrice: 1200, category: 'carpinteria' },
      { description: 'Vestidor a medida (módulos)',                       unit: 'm²', unitPrice: 320,  category: 'carpinteria' },
      { description: 'Ventana PVC doble hoja + vidrio climalit',         unit: 'ud', unitPrice: 580,  category: 'carpinteria' },
      { description: 'Ventana aluminio RPT doble hoja + vidrio',         unit: 'ud', unitPrice: 650,  category: 'carpinteria' },
      { description: 'Persiana motorizada exterior',                      unit: 'ud', unitPrice: 320,  category: 'carpinteria' },
      { description: 'Tarima exterior/terraza (composite)',               unit: 'm²', unitPrice: 65,   category: 'carpinteria' },
      { description: 'Estanterías a medida (por módulo)',                 unit: 'ud', unitPrice: 180,  category: 'carpinteria' },
      { description: 'Lacado/pintado carpintería interior (puerta)',     unit: 'ud', unitPrice: 95,   category: 'carpinteria' },
    ],
  },

  // ── ALBAÑILERÍA ─────────────────────────────────────────────────────────────
  albanileria: {
    label: 'Albañilería',
    icon: '🧱',
    color: '#fb923c',
    items: [
      { description: 'Tabique de ladrillo hueco (7cm)',                  unit: 'm²', unitPrice: 28,  category: 'albanileria' },
      { description: 'Pared de pladur 10cm (doble placa)',               unit: 'm²', unitPrice: 32,  category: 'albanileria' },
      { description: 'Derribo tabique/pared no estructural',             unit: 'm²', unitPrice: 22,  category: 'albanileria' },
      { description: 'Enfoscado de paredes (cemento)',                   unit: 'm²', unitPrice: 14,  category: 'albanileria' },
      { description: 'Revoco/guarnecido de yeso paredes',                unit: 'm²', unitPrice: 12,  category: 'albanileria' },
      { description: 'Impermeabilización terraza (lámina asfáltica)',    unit: 'm²', unitPrice: 35,  category: 'albanileria' },
      { description: 'Solera de hormigón 10cm',                          unit: 'm²', unitPrice: 18,  category: 'albanileria' },
      { description: 'Apertura de hueco para puerta en tabique',         unit: 'ud', unitPrice: 180, category: 'albanileria' },
      { description: 'Apertura de hueco para ventana en fachada',        unit: 'ud', unitPrice: 350, category: 'albanileria' },
      { description: 'Recrecido suelo con mortero (5cm)',                unit: 'm²', unitPrice: 14,  category: 'albanileria' },
      { description: 'Rejuntado azulejos/porcelánico',                   unit: 'm²', unitPrice: 8,   category: 'albanileria' },
      { description: 'Silicona sanitaria (baño/cocina)',                 unit: 'ml', unitPrice: 6,   category: 'albanileria' },
    ],
  },

  // ── REFORMA INTEGRAL ────────────────────────────────────────────────────────
  reforma_integral: {
    label: 'Reforma integral',
    icon: '🏗️',
    color: '#c084fc',
    items: [
      { description: 'Reforma integral vivienda (mano de obra, sin mat.)', unit: 'm²', unitPrice: 280, category: 'reforma_integral' },
      { description: 'Reforma integral piso 60m² (todo incluido)',         unit: 'ud', unitPrice: 38000, category: 'reforma_integral' },
      { description: 'Reforma integral piso 80m² (todo incluido)',         unit: 'ud', unitPrice: 50000, category: 'reforma_integral' },
      { description: 'Reforma integral piso 100m² (todo incluido)',        unit: 'ud', unitPrice: 62000, category: 'reforma_integral' },
      { description: 'Reforma baño completo (mat. gama media incluidos)',  unit: 'ud', unitPrice: 4500,  category: 'reforma_integral' },
      { description: 'Reforma cocina completa (mat. gama media incluidos)',unit: 'ud', unitPrice: 8000,  category: 'reforma_integral' },
      { description: 'Reforma salón/comedor (pintura + suelo + techo)',   unit: 'ud', unitPrice: 3200,  category: 'reforma_integral' },
      { description: 'Reforma dormitorio (pintura + suelo + armario)',    unit: 'ud', unitPrice: 2800,  category: 'reforma_integral' },
      { description: 'Gestión de residuos (contenedor)',                  unit: 'ud', unitPrice: 280,   category: 'reforma_integral' },
      { description: 'Proyecto visado arquitecto',                        unit: 'ud', unitPrice: 1200,  category: 'reforma_integral' },
      { description: 'Dirección de obra',                                 unit: 'h',  unitPrice: 85,    category: 'reforma_integral' },
      { description: 'Licencia de obras menor (gestión)',                 unit: 'ud', unitPrice: 350,   category: 'reforma_integral' },
    ],
  },
}

// Lista plana de todas las partidas para búsqueda
export const ALL_ITEMS = Object.values(RENOVATION_CATALOG)
  .flatMap(cat => cat.items)

// Colores por categoría
export function getCategoryColor(category) {
  return RENOVATION_CATALOG[category]?.color ?? '#f0a500'
}

// Label por categoría
export function getCategoryLabel(category) {
  return RENOVATION_CATALOG[category]?.label ?? category
}
