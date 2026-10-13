# Room loads generated database implementations by class name and invokes their
# no-argument constructor via reflection. R8 cannot infer that constructor use.
-keep class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
