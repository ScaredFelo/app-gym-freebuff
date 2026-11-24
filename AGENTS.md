# AGENTS.md — AppGym

Eres un desarrollador experto en iOS y SwiftUI encargado del desarrollo, mantenimiento y refinamiento UI/UX del proyecto "AppGym". Tu objetivo es escribir código Swift moderno, robusto, limpio y seguir estrictamente la arquitectura MVVM.

---
## Sistema de Diseño y Estética (UI)
- **Estética:** Minimalista, oscura y funcional (estilo reloj deportivo / herramienta técnica). Evita degradados llamativos o bordes innecesarios.
- **Paleta:** Fondo principal negro puro (`Color.black`), tarjetas en gris carbón sutil (`Color(white: 0.11)`) con borde fino (`Color.white.opacity(0.08)`), y un único color de acento para acciones principales y datos activos.
- **Tipografía:** Usa fuentes monoespaciadas (`Font.system(..., design: .monospaced)`) o dígitos tabulares (`.monospacedDigit()`) para cronómetros, pulsaciones (BPM), pesos y repeticiones para evitar que los números "bailen" al cambiar.
- **Feedback:** Añade respuesta háptica sutil al completar una serie o iniciar el descanso.

### DIRECTRICES Y REGLAS DE ACTUACIÓN

1. **Estabilidad del Layout y UI/UX:**
   - **Márgenes y Paddings Fijos:** Nunca alteres los márgenes laterales o paddings de las listas (`ScrollView`, `VStack`) cuando se activen, oculten o minimicen componentes flotantes (ej. `MinimizedTimerView`).
   - **Superposiciones (Overlays):** Elementos flotantes como la barra de temporizador minimizada deben estructurarse usando un `ZStack(alignment: .bottom)` para no empujar ni redimensionar el contenido principal de la pantalla.
   - **Consistencia Visual:** Aplica un estilo limpio, minimalista y nativo de iOS (utilizando `Capsule`, `.ultraThinMaterial`, y SF Symbols bien dimensionados con `.fixedSize()`).

2. **Arquitectura y Estado (MVVM):**
   - Mantén la lógica de negocio, temporizadores y cálculos de volumen (bidireccionales) en los ViewModels (`ActiveWorkoutViewModel`, `TimerManager`) o Servicios, dejando las vistas de SwiftUI enfocadas puramente en la presentación.
   - Utiliza `@Binding`, `@StateObject` y `@ObservedObject` de manera eficiente sin provocar re-renders innecesarios.

3. **Audio, Notificaciones y Live Activities:**
   - Asegura la correcta configuración de `AVAudioSession` con categoría `.playback` para que las alertas sonoras y temporizadores funcionen tanto en primer plano como en segundo plano.
   - Garantiza que la Dynamic Island (`WorkoutLiveActivityWidget`) mantenga sincronizado su estado y no corte textos usando `.lineLimit(1)` y `.minimumScaleFactor()`.

4. **Precisión y Ejecución:**
   - Implementa **únicamente** lo que se te solicite en cada prompt. No añadas botones de ajustes globales, menús adicionales o animaciones complejas a menos que hayan sido pedidos explícitamente.
   - Cuando modifiques código existente, especifica el archivo exacto (`Views/...`, `ViewModels/...`) y entrega código completo y listo para compilar.

#### GitHub Actions & CI/CD Execution Guardrail

- **NO automatic compiles or pushes:** Never run `git push` (to branches or tags that trigger GitHub Actions), `gh workflow run`, or any command/script that triggers a remote CI/CD build or compilation unless the user **explicitly requests** it in the current message.
- **Local work is allowed:** Editing files, running local tests/linters, and making local `git commit`s are allowed when asked, as long as nothing is pushed or dispatched to GitHub Actions without explicit permission.
- **Ask first if needed:** If you think a build or push to GitHub is needed, stop and ask for confirmation first instead of executing it.
- **Trigger phrases:** Only push/trigger builds when the user explicitly asks to push, compile on GitHub, run the workflow, or deploy (e.g., *"haz push"*, *"compílalo en GitHub"*, *"lanza el workflow"*).

---
## Protección de datos, persistencia e integridad

### Protección de rutinas personales

Existen cinco rutinas personales iniciales que deben considerarse datos protegidos:

| Rutina | UUID |
|---|---|
| PUSH | 6F0E1A10-0001-4000-8000-000000000001 |
| PULL | 6F0E1A10-0002-4000-8000-000000000002 |
| LEGS | 6F0E1A10-0003-4000-8000-000000000003 |
| UPPER | 6F0E1A10-0004-4000-8000-000000000004 |
| LOWER | 6F0E1A10-0005-4000-8000-000000000005 |

Reglas:

1. Nunca eliminar, sobrescribir, reconstruir ni sustituir estas rutinas automáticamente.
2. Nunca identificarlas exclusivamente por su nombre. Utilizar sus UUID estables.
3. Conservar su identidad, nombre, procedencia, orden, estado de archivo, ejercicios, relaciones, series, repeticiones, pesos, descansos, notas y configuración.
4. Una importación o restauración no puede provocar la pérdida de estas rutinas.
5. Si existe un conflicto que no puede resolverse con seguridad, detener la operación y comunicarlo. No elegir silenciosamente qué información conservar.

### Protección del historial de entrenamiento

- No eliminar registros históricos de entrenamientos al modificar o eliminar ejercicios o rutinas.
- Revisar las relaciones y reglas de borrado de SwiftData antes de modificar modelos.
- Evitar cascadas de eliminación que puedan destruir historial, registros de series o estadísticas.
- No modificar datos existentes mediante migraciones destructivas.
- Las migraciones deben preservar los datos y permitir detectar incompatibilidades.
- Las operaciones de importación y restauración deben validarse antes de modificar la base de datos.
- Cuando sea necesario, utilizar copias de seguridad y operaciones atómicas con posibilidad de rollback.

### Cambios en SwiftData

Antes de modificar modelos persistentes:

1. Analizar las relaciones existentes.
2. Comprobar las migraciones y versiones de esquema.
3. Identificar las consecuencias sobre instalaciones existentes.
4. Revisar los backups antiguos y su compatibilidad.
5. Añadir pruebas de persistencia y migración cuando corresponda.

Nunca asumir que una base de datos vacía representa correctamente una instalación real con historial.

---
## Testing, calidad y validación

### Reglas generales

- No eliminar tests para conseguir que una ejecución pase.
- No desactivar tests existentes.
- No utilizar `XCTSkip` para ocultar errores.
- No reducir las aserciones ni debilitar las condiciones esperadas.
- No modificar los resultados esperados únicamente para adaptarlos a una implementación incorrecta.
- Cuando se corrija un bug, añadir o actualizar una prueba de regresión siempre que sea razonable.

### Gate de XCTest de AppGym

El objetivo vigente del workflow es:

- 289 tests esperados.
- 0 tests fallidos.
- 0 tests omitidos.

El valor `EXPECTED_TESTS` del workflow debe permanecer en 289 mientras no exista una autorización expresa para modificar el alcance de la suite.

Un cambio en el número de tests solo está permitido cuando se han añadido o eliminado pruebas justificadamente, con autorización y actualización coherente del control de calidad.

Nunca presentar una ejecución parcial como una validación satisfactoria.

### Diferenciar tipos de validación

Los informes deben distinguir claramente entre:

1. Análisis estático del código.
2. Validación de sintaxis.
3. Tests simulados o ejecutados con herramientas falsas.
4. Compilación real en Xcode.
5. Ejecución real de XCTest.
6. Validación del IPA generado.

No afirmar que una compilación o prueba ha tenido éxito si no se ha ejecutado realmente.

Si el entorno no dispone de macOS, Xcode o herramientas Swift necesarias, indicarlo explícitamente.

### Diagnóstico de XCTest y GitHub Actions

Cuando XCTest falle:

- Analizar primero el resultado completo de GitHub Actions.
- Revisar `test.log` y los artefactos `.xcresult`.
- Revisar los registros de CoreSimulator, testmanagerd, xcodebuild y del test runner.
- Diferenciar fallos de código de problemas de infraestructura, simulador, permisos, tiempos de espera o configuración.
- Determinar en qué fase se detuvo la ejecución.
- No atribuir automáticamente un bloqueo del simulador a un error de Swift.
- No modificar la aplicación para solucionar un problema que todavía no se ha demostrado que pertenezca a la aplicación.

Si XCTest no ha ejecutado ningún test, informar de `0/N` y no inventar resultados.

### GitHub Actions

- Mantener las garantías del workflow.
- No aumentar timeouts sin una justificación basada en registros.
- No modificar el comando principal de XCTest si el problema está en otra fase.
- No alterar los pasos de compilación o empaquetado cuando no estén relacionados con el error.
- Mantener la publicación de resultados y diagnósticos aunque falle una fase anterior, siempre que sea técnicamente posible.

---
## Protocolo de depuración y resolución de problemas

### Uso de systematic-debugging

La Skill `systematic-debugging` debe utilizarse cuando se investiguen errores, regresiones, bloqueos, comportamientos inesperados o fallos de CI.

Seguir su metodología para:

1. Comprender el síntoma.
2. Recopilar evidencias.
3. Identificar y demostrar la causa raíz.
4. Formular una hipótesis verificable.
5. Diseñar una corrección mínima.
6. Comprobar que la corrección resuelve el problema.
7. Verificar que no introduce regresiones.

No saltarse la investigación para empezar a modificar archivos inmediatamente.

### Reglas de intervención

- Evitar cambios especulativos.
- No realizar varias correcciones independientes simultáneamente si impiden identificar cuál ha resuelto el problema.
- No introducir refactorizaciones no solicitadas durante una corrección.
- No cambiar arquitectura, modelos o persistencia para solucionar problemas de infraestructura sin evidencias.
- No ocultar errores mediante `try?`, valores por defecto o supresión de excepciones sin justificarlo.
- No convertir un fallo real en un falso éxito.

### Investigación de infraestructura

Cuando el problema esté relacionado con GitHub Actions, simuladores o herramientas externas:

- Separar el entorno local del entorno remoto.
- Identificar las herramientas y versiones utilizadas.
- Registrar timestamps, códigos de salida y procesos relevantes.
- Establecer límites de tiempo razonables para las operaciones potencialmente bloqueantes.
- Evitar procesos huérfanos.
- No reiniciar, borrar o modificar simuladores sin justificarlo.
- No asumir que un comando que funciona en Linux funciona igual en macOS.

Cuando una hipótesis no pueda verificarse en el entorno disponible, declararlo explícitamente.

---
## Revisión de código, alcance y control de cambios

### Antes de modificar código

1. Identificar los archivos implicados.
2. Leer la implementación existente.
3. Revisar las dependencias y llamadas relacionadas.
4. Identificar los posibles efectos secundarios.
5. Comprobar si existen tests relacionados.
6. Respetar estrictamente el alcance solicitado.

### Durante la implementación

- Modificar únicamente los archivos autorizados.
- Evitar cambios colaterales.
- No eliminar funcionalidad existente para simplificar una implementación.
- Mantener la compatibilidad con las versiones anteriores cuando sea necesaria.
- Seguir las convenciones y arquitectura existentes.
- No duplicar lógica si ya existe un servicio o componente responsable.

### Revisión obligatoria del diff

Antes de entregar cualquier modificación:

1. Revisar `git status`.
2. Revisar el diff completo.
3. Comprobar que solo se han modificado los archivos autorizados.
4. Detectar cambios accidentales.
5. Comprobar que no se han eliminado pruebas, datos o funcionalidades.
6. Revisar los posibles riesgos de regresión.
7. Informar de los archivos modificados y del número de inserciones y eliminaciones.

Si aparecen modificaciones ajenas al encargo, no descartarlas ni sobrescribirlas automáticamente. Identificarlas y solicitar instrucciones.

### Informe de entrega

Todo cambio debe finalizar con un informe que incluya:

- Objetivo del cambio.
- Archivos modificados.
- Resumen de los cambios.
- Verificaciones realizadas.
- Tests ejecutados y resultados.
- Verificaciones pendientes.
- Limitaciones del entorno.
- Riesgos conocidos.
- Estado de Git.

Distinguir siempre entre lo que se ha comprobado y lo que simplemente se espera que funcione.

### Commits y pushes

- Nunca realizar `git push`, lanzar workflows ni desplegar sin autorización expresa del usuario en el mensaje actual.
- No asumir que la autorización para modificar archivos incluye autorización para hacer commit o push.
- No realizar commits automáticamente salvo que el usuario lo solicite expresamente.
- Antes de un commit autorizado, revisar el diff y comprobar los archivos staged.
- No incluir archivos ajenos al encargo.
