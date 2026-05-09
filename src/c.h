#ifndef GWIN_C_H
#define GWIN_C_H

#include <stddef.h>
#include <stdint.h>

typedef void* gpointer;
typedef const void* gconstpointer;
typedef int gboolean;
typedef int32_t gint32;
typedef uint32_t guint32;
typedef int64_t gint64;
typedef uint64_t guint64;
typedef size_t gsize;
typedef char gchar;

typedef struct _GList GList;
struct _GList {
    gpointer data;
    GList *next;
    GList *prev;
};

typedef struct _GSList GSList;
struct _GSList {
    gpointer data;
    GSList *next;
};

typedef struct _GError GError;
struct _GError {
    uint32_t domain;
    int code;
    char *message;
};

typedef struct _GDBusConnection GDBusConnection;
typedef struct _GVariant GVariant;
typedef struct _GAppInfo GAppInfo;
typedef struct _GIcon GIcon;
typedef struct _GDesktopAppInfo GDesktopAppInfo;

typedef enum {
    G_BUS_TYPE_STARTER = -1,
    G_BUS_TYPE_NONE = 0,
    G_BUS_TYPE_SYSTEM = 1,
    G_BUS_TYPE_SESSION = 2
} GBusType;

typedef enum {
    G_DBUS_CALL_FLAGS_NONE = 0,
    G_DBUS_CALL_FLAGS_NO_AUTO_START = (1 << 0),
    G_DBUS_CALL_FLAGS_ALLOW_INTERACTIVE_AUTHORIZATION = (1 << 1)
} GDBusCallFlags;

// Functions
GDBusConnection *g_bus_get_sync (GBusType bus_type, void *cancellable, GError **error);
GVariant *g_dbus_connection_call_sync (GDBusConnection *connection, const gchar *bus_name, const gchar *object_path, const gchar *interface_name, const gchar *method_name, GVariant *parameters, const void *reply_type, GDBusCallFlags flags, gint32 timeout_msec, void *cancellable, GError **error);
void g_variant_unref (GVariant *value);
void g_variant_get (GVariant *value, const gchar *format_string, ...);
GVariant *g_variant_new (const gchar *format_string, ...);
void g_object_unref (gpointer object);
void g_error_free (GError *error);

GList *g_app_info_get_all (void);
const gchar *g_app_info_get_name (GAppInfo *appinfo);
const gchar *g_app_info_get_id (GAppInfo *appinfo);
GIcon *g_app_info_get_icon (GAppInfo *appinfo);
gchar *g_icon_to_string (GIcon *icon);
void g_list_free (GList *list);
uint32_t g_list_length (GList *list);
void g_free (gpointer mem);

GDesktopAppInfo *g_desktop_app_info_new (const gchar *desktop_id);
gboolean g_app_info_launch (GAppInfo *appinfo, GList *files, void *launch_context, GError **error);

#endif
