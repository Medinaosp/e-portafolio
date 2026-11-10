# E-portafolio académico

Sitio académico para Bases de Datos 2, construido con Astro.

## Ejecutar localmente

Requiere Node.js 22.12 o posterior.

```sh
npm install
npm run dev
```

Abre la dirección local que muestra Astro en la terminal. La configuración conserva la base `/e-portafolio` usada en GitHub Pages.

## Contenido

- `src/pages/index.astro`: página principal, prácticas, reflexiones y capturas.
- `public/evidencias/`: recortes de resultados del informe grupal del Taller Integrador Banco Andino.
- `public/material/sql/`: prácticas de SQL y PL/SQL.
- `public/material/sql/banco-andino/`: scripts del taller de dos sesiones, índices, SQL avanzado y reto integrador.
- `public/foto/` y `public/video/`: foto y video de presentación.

Los scripts `00_setup.sql` y `99_limpieza.sql` preparan y eliminan objetos del esquema de práctica. Úsalos únicamente en un esquema de laboratorio y sigue las indicaciones de `LEEME.txt`; no se ejecutaron al preparar el portafolio.

Las capturas de la galería proceden de una entrega grupal. El paquete no incluye capturas de ejecución de los módulos PL/SQL.
