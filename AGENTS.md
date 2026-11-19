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
