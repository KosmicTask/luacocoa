-- Adapted from:
-- http://developer.apple.com/library/mac/#documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_drawing/opengl_drawing.html

LuaCocoa.import("Cocoa")
LuaCocoa.import("OpenGL")

SimpleLuaOpenGLView = LuaCocoa.CreateClass("SimpleLuaOpenGLView", NSOpenGLView)

SimpleLuaOpenGLView["drawRect_"] = 
{
	-- TODO: Provide an API to get signatures for methods and types.
	-- Currently, if the method signature is already defined in Obj-C by the super-class,
	-- then I think it is okay if the signature is imperfect (so don't worry about 32-bit vs. 64-bit).
	"-v@:{CGRect={CGPoint=dd}{CGSize=dd}}",
	function (self, the_rect)
		glClearColor(0, 0, 0, 0);
		glClear(GL_COLOR_BUFFER_BIT);

		glColor3f(1.0, 0.85, 0.35);
		glBegin(GL_TRIANGLES);
			glVertex3f(  0.0,  0.6, 0.0);
			glVertex3f( -0.2, -0.3, 0.0);
			glVertex3f(  0.2, -0.3, 0.0);
		glEnd();

		glFlush();
	end
}

