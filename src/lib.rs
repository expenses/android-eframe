use winit::event_loop::EventLoop;
use winit::platform::android::EventLoopBuilderExtAndroid;

#[no_mangle]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    let event_loop = EventLoop::builder().with_android_app(app).build().unwrap();
    glutin_examples::main(event_loop).unwrap()
}

mod glutin_examples {
    use glow::HasContext;
    use std::error::Error;
    use std::num::NonZeroU32;
    use std::sync::Arc;

    use raw_window_handle::HasWindowHandle;
    use winit::application::ApplicationHandler;
    use winit::event::{KeyEvent, WindowEvent};
    use winit::keyboard::{Key, NamedKey};
    use winit::window::Window;

    use glutin::config::{Config, ConfigTemplateBuilder};
    use glutin::context::{
        ContextApi, ContextAttributesBuilder, NotCurrentContext, PossiblyCurrentContext, Version,
    };
    use glutin::display::GetGlDisplay;
    use glutin::prelude::*;
    use glutin::surface::{Surface, SwapInterval, WindowSurface};

    use glutin_winit::{DisplayBuilder, GlWindow};

    struct App {
        template: ConfigTemplateBuilder,
        display_builder: DisplayBuilder,
        exit_state: Result<(), Box<dyn Error>>,
        not_current_gl_context: Option<NotCurrentContext>,
        renderer: Option<Renderer>,
        // NOTE: `AppState` carries the `Window`, thus it should be dropped after everything else.
        state: Option<AppState>,
    }

    pub fn main(event_loop: winit::event_loop::EventLoop<()>) -> Result<(), Box<dyn Error>> {
        let window_attributes = Window::default_attributes()
            .with_transparent(true)
            .with_title("Glutin triangle gradient example (press Escape to exit)");

        // The template will match only the configurations supporting rendering
        // to windows.
        //
        // XXX We force transparency only on macOS, given that EGL on X11 doesn't
        // have it, but we still want to show window. The macOS situation is like
        // that, because we can query only one config at a time on it, but all
        // normal platforms will return multiple configs, so we can find the config
        // with transparency ourselves inside the `reduce`.
        let template = ConfigTemplateBuilder::new()
            .with_alpha_size(8)
            .with_transparency(false);

        let display_builder = DisplayBuilder::new().with_window_attributes(Some(window_attributes));

        let mut app = App {
            template,
            display_builder,
            exit_state: Ok(()),
            not_current_gl_context: None,
            state: None,
            renderer: None,
        };
        event_loop.run_app(&mut app)?;

        app.exit_state
    }

    impl ApplicationHandler for App {
        fn resumed(&mut self, event_loop: &winit::event_loop::ActiveEventLoop) {
            let (mut window, gl_config) = match self.display_builder.clone().build(
                event_loop,
                self.template.clone(),
                gl_config_picker,
            ) {
                Ok(ok) => ok,
                Err(e) => {
                    self.exit_state = Err(e);
                    event_loop.exit();
                    return;
                }
            };

            println!("Picked a config with {} samples", gl_config.num_samples());

            let raw_window_handle = window
                .as_ref()
                .and_then(|window| window.window_handle().ok())
                .map(|handle| handle.as_raw());

            // XXX The display could be obtained from any object created by it, so we can
            // query it from the config.
            let gl_display = gl_config.display();

            // The context creation part.
            let context_attributes = ContextAttributesBuilder::new().build(raw_window_handle);

            // Since glutin by default tries to create OpenGL core context, which may not be
            // present we should try gles.
            let fallback_context_attributes = ContextAttributesBuilder::new()
                .with_context_api(ContextApi::Gles(None))
                .build(raw_window_handle);

            // There are also some old devices that support neither modern OpenGL nor GLES.
            // To support these we can try and create a 2.1 context.
            let legacy_context_attributes = ContextAttributesBuilder::new()
                .with_context_api(ContextApi::OpenGl(Some(Version::new(2, 1))))
                .build(raw_window_handle);

            self.not_current_gl_context.replace(unsafe {
                gl_display
                    .create_context(&gl_config, &context_attributes)
                    .unwrap_or_else(|_| {
                        gl_display
                            .create_context(&gl_config, &fallback_context_attributes)
                            .unwrap_or_else(|_| {
                                gl_display
                                    .create_context(&gl_config, &legacy_context_attributes)
                                    .expect("failed to create context")
                            })
                    })
            });

            println!("Android window available");

            let window = window.take().unwrap_or_else(|| {
                let window_attributes = Window::default_attributes()
                    .with_transparent(true)
                    .with_title("Glutin triangle gradient example (press Escape to exit)");
                glutin_winit::finalize_window(event_loop, window_attributes, &gl_config).unwrap()
            });

            let attrs = window
                .build_surface_attributes(Default::default())
                .expect("Failed to build surface attributes");
            let gl_surface = unsafe {
                gl_config
                    .display()
                    .create_window_surface(&gl_config, &attrs)
                    .unwrap()
            };

            // Make it current.
            let gl_context = self
                .not_current_gl_context
                .take()
                .unwrap()
                .make_current(&gl_surface)
                .unwrap();

            // The context needs to be current for the Renderer to set up shaders and
            // buffers. It also performs function loading, which needs a current context on
            // WGL.
            self.renderer
                .get_or_insert_with(|| Renderer::new(&gl_display, &event_loop));

            // Try setting vsync.
            if let Err(res) = gl_surface
                .set_swap_interval(&gl_context, SwapInterval::Wait(NonZeroU32::new(1).unwrap()))
            {
                eprintln!("Error setting vsync: {res:?}");
            }

            assert!(self
                .state
                .replace(AppState {
                    gl_context,
                    gl_surface,
                    window
                })
                .is_none());
        }

        fn suspended(&mut self, _event_loop: &winit::event_loop::ActiveEventLoop) {
            // This event is only raised on Android, where the backing NativeWindow for a GL
            // Surface can appear and disappear at any moment.
            println!("Android window removed");

            // Destroy the GL Surface and un-current the GL Context before ndk-glue releases
            // the window back to the system.
            let gl_context = self.state.take().unwrap().gl_context;
            assert!(self
                .not_current_gl_context
                .replace(gl_context.make_not_current().unwrap())
                .is_none());
        }

        fn window_event(
            &mut self,
            event_loop: &winit::event_loop::ActiveEventLoop,
            _window_id: winit::window::WindowId,
            event: WindowEvent,
        ) {
            if let (Some(renderer), Some(AppState { window, .. })) =
                (self.renderer.as_mut(), self.state.as_ref())
            {
                renderer.egui_glow.on_window_event(&window, &event);
            }

            match event {
                WindowEvent::Resized(size) if size.width != 0 && size.height != 0 => {
                    // Some platforms like EGL require resizing GL surface to update the size
                    // Notable platforms here are Wayland and macOS, other don't require it
                    // and the function is no-op, but it's wise to resize it for portability
                    // reasons.
                    if let Some(AppState {
                        gl_context,
                        gl_surface,
                        window: _,
                    }) = self.state.as_ref()
                    {
                        gl_surface.resize(
                            gl_context,
                            NonZeroU32::new(size.width).unwrap(),
                            NonZeroU32::new(size.height).unwrap(),
                        );
                        let renderer = self.renderer.as_ref().unwrap();
                        renderer.resize(size.width as i32, size.height as i32);
                    }
                }
                WindowEvent::CloseRequested
                | WindowEvent::KeyboardInput {
                    event:
                        KeyEvent {
                            logical_key: Key::Named(NamedKey::Escape),
                            ..
                        },
                    ..
                } => event_loop.exit(),
                _ => (),
            }
        }

        fn about_to_wait(&mut self, _event_loop: &winit::event_loop::ActiveEventLoop) {
            if let Some(AppState {
                gl_context,
                gl_surface,
                window,
            }) = self.state.as_ref()
            {
                let renderer = self.renderer.as_mut().unwrap();
                renderer.draw(&window);

                window.request_redraw();

                gl_surface.swap_buffers(gl_context).unwrap();
            }
        }
    }

    struct AppState {
        gl_context: PossiblyCurrentContext,
        gl_surface: Surface<WindowSurface>,
        // NOTE: Window should be dropped after all resources created using its
        // raw-window-handle.
        window: Window,
    }

    // Find the config with the maximum number of samples, so our triangle will be
    // smooth.
    pub fn gl_config_picker(configs: Box<dyn Iterator<Item = Config> + '_>) -> Config {
        configs
            .reduce(|accum, config| {
                let transparency_check = config.supports_transparency().unwrap_or(false)
                    & !accum.supports_transparency().unwrap_or(false);

                if transparency_check || config.num_samples() > accum.num_samples() {
                    config
                } else {
                    accum
                }
            })
            .unwrap()
    }

    pub struct Renderer {
        gl: Arc<glow::Context>,
        egui_glow: egui_glow::EguiGlow,
        demo_windows: egui_demo_lib::DemoWindows,
    }

    impl Renderer {
        pub fn new<D: GlDisplay>(
            gl_display: &D,
            event_loop: &winit::event_loop::ActiveEventLoop,
        ) -> Self {
            unsafe {
                let gl = Arc::new(glow::Context::from_loader_function_cstr(|s| {
                    gl_display.get_proc_address(s)
                }));

                let egui_glow = egui_glow::EguiGlow::new(event_loop, gl.clone(), None, None);

                Self {
                    gl,
                    egui_glow,
                    demo_windows: Default::default(),
                }
            }
        }

        pub fn draw(&mut self, window: &Window) {
            //self.draw_with_clear_color(0.5, 0.1, 0.1, 0.9);
            self.egui_glow.run(&window, |mut egui_ctx| {
                self.demo_windows.ui(&mut egui_ctx);
            });
            self.egui_glow.paint(window);
        }

        pub fn draw_with_clear_color(&self, red: f32, green: f32, blue: f32, alpha: f32) {
            unsafe {
                self.gl.clear_color(red, green, blue, alpha);
                self.gl.clear(glow::COLOR_BUFFER_BIT);
            }
        }

        pub fn resize(&self, width: i32, height: i32) {
            unsafe {
                self.gl.viewport(0, 0, width, height);
            }
        }
    }
}
