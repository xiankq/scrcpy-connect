package android.view;

public final class Surface {
    public boolean released;

    public void release() {
        if (released) {
            throw new AssertionError("surface released twice");
        }
        released = true;
    }
}
