export default {
  // Nav
  nav: {
    projects: 'Proyectos',
    create: 'Crear',
    explore: 'Explorar',
    profile: 'Perfil',
  },
  // Home
  home: {
    title: 'Mis Proyectos',
    empty: 'Aún no tienes proyectos',
    emptyHint: 'Pulsa el botón + para crear tu primera medición',
    recent: 'Recientes',
    all: 'Todos',
  },
  // Create modal
  create: {
    title: 'Nuevo Proyecto',
    options: {
      scan: {
        label: 'Medir Espacio',
        desc: 'Abre la cámara y marca las esquinas del suelo para calcular m²',
      },
      photo: {
        label: 'Alzar desde Foto',
        desc: 'Sube una foto y genera un modelo de referencia con IA',
      },
      plan: {
        label: 'Dibujar Plano',
        desc: 'Dibuja el plano de planta manualmente con el editor 2D',
      },
      model3d: {
        label: 'Modelo 3D',
        desc: 'Construye o edita la habitación en el visor tridimensional',
      },
      upload: {
        label: 'Subir Archivos',
        desc: 'Importa fotos, vídeos o planos existentes',
      },
      manual: {
        label: 'Entrada Manual',
        desc: 'Introduce las dimensiones directamente en metros',
      },
    },
  },
  // Scanner
  scanner: {
    title: 'Medición con Cámara',
    step1: 'Apunta la cámara al suelo de la estancia',
    step2: 'Toca cada esquina del suelo en orden',
    step3: 'Marca una pared de longitud conocida para la escala',
    openCamera: 'Abrir Cámara',
    corners: 'esquina',
    corners_pl: 'esquinas',
    marked: 'marcada',
    marked_pl: 'marcadas',
    tapHint: 'Toca las esquinas del suelo en orden',
    undo: 'Deshacer',
    done: 'Listo',
    refHint0: 'Toca el inicio de una pared conocida',
    refHint1: 'Toca el final de esa pared',
    refHint2: '✓ Referencia marcada',
    refDist: '¿Cuánto mide esa distancia?',
    calculate: 'Calcular m²',
    rescan: 'Re-escanear',
  },
  // Manual
  manual: {
    title: 'Medición Manual',
    room: 'Nombre de la estancia',
    roomPlaceholder: 'Ej. Salón',
    width: 'Ancho (m)',
    length: 'Largo (m)',
    area: 'Superficie calculada',
    continue: 'Continuar',
    back: 'Volver',
  },
  // Budget
  budget: {
    title: 'Valoración',
    company: 'Empresa',
    client: 'Cliente',
    date: 'Fecha',
    room: 'Estancia',
    dimensions: 'Dimensiones',
    surface: 'Superficie',
    adjustSurface: 'Ajustar superficie (m²)',
    partitions: 'Partidas',
    add: 'Añadir',
    description: 'Descripción',
    unit: 'Unidad',
    unitPrice: 'Precio u.',
    qty: 'Cant.',
    subtotal: 'Subtotal',
    taxRate: 'IVA (%)',
    total: 'Total',
    export: 'Exportar valoración',
    rescan: 'Nueva medición',
    footer: 'Generado con mi-render · Zerbitecni',
    units: { sqm: 'm²', ml: 'm lineal', ud: 'ud', h: 'hora', set: 'set' },
  },
  // Profile
  profile: {
    title: 'Perfil',
    account: 'Cuenta',
    language: 'Idioma',
    settings: 'Configuración',
    billing: 'Facturación',
    help: 'Ayuda',
    updates: 'Buscar actualizaciones',
    helpCenter: 'Centro de ayuda',
    whatsNew: '¿Qué hay de nuevo?',
    reportBug: 'Informar de un error',
    version: 'Versión',
    signOut: 'Cerrar sesión',
  },
  // Explore
  explore: {
    title: 'Explorar',
    subtitle: 'Plantillas, guías de precios y recursos',
    priceGuide: 'Guía de precios',
    templates: 'Plantillas',
    tutorials: 'Tutoriales',
  },
  // Common
  common: {
    cancel: 'Cancelar',
    save: 'Guardar',
    delete: 'Eliminar',
    edit: 'Editar',
    close: 'Cerrar',
    loading: 'Cargando…',
    error: 'Error',
    or: 'o',
    sqm: 'm²',
    meters: 'm',
  },
}
