import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "npm:@supabase/server@^1";

interface OwnerPayload {
  email: string;
  first_name: string;
  last_name: string;
  phone?: string | null;
  address?: string | null;
  city?: string | null;
  postal_code?: string | null;
  legal_name?: string | null;
  tax_id?: string | null;
  notes?: string | null;
}

export default {
  fetch: withSupabase({ auth: "user" }, async (req, ctx) => {
    if (req.method !== "POST") {
      return Response.json(
        { error: "Método no permitido" },
        { status: 405 },
      );
    }

    try {
      const userId = ctx.userClaims?.id;

      if (!userId) {
        return Response.json(
          { error: "Usuario no autenticado." },
          { status: 401 },
        );
      }

      // Comprobar que quien realiza la operación es administrador
      const { data: adminProfile, error: adminProfileError } =
        await ctx.supabaseAdmin
          .from("profiles")
          .select("id, role, active")
          .eq("id", userId)
          .maybeSingle();

      if (adminProfileError) {
        console.error(
          "Error comprobando administrador:",
          adminProfileError,
        );

        return Response.json(
          { error: "No se pudo comprobar el usuario administrador." },
          { status: 500 },
        );
      }

      if (
        !adminProfile ||
        adminProfile.role !== "admin" ||
        adminProfile.active !== true
      ) {
        return Response.json(
          { error: "No tienes permisos para crear propietarios." },
          { status: 403 },
        );
      }

      const body: OwnerPayload = await req.json();

      const email = body.email?.trim().toLowerCase();
      const firstName = body.first_name?.trim();
      const lastName = body.last_name?.trim();

      // La contraseña NO se solicita.
      // El propietario la establecerá mediante la invitación.
      if (!email || !firstName || !lastName) {
        return Response.json(
          {
            error:
              "Faltan datos obligatorios: email, first_name y last_name.",
          },
          { status: 400 },
        );
      }

      // Crear usuario mediante invitación.
      // El propietario recibirá un correo y establecerá
      // personalmente su contraseña.
      const { data: authData, error: authError } =
        await ctx.supabaseAdmin.auth.admin.inviteUserByEmail(email, {
          redirectTo:
            "https://webjisa.github.io/MiEspacioParaCelebrar/activar-cuenta.html",
        });

      if (authError) {
        console.error(
          "Error enviando invitación al propietario:",
          authError,
        );

        return Response.json(
          { error: authError.message },
          { status: 400 },
        );
      }

      if (!authData.user) {
        return Response.json(
          { error: "No se pudo crear la invitación del propietario." },
          { status: 500 },
        );
      }

      const newUserId = authData.user.id;

      // Crear perfil y registro de propietario
      const { data: ownerId, error: ownerError } =
        await ctx.supabase.rpc("create_owner_profile", {
          p_user_id: newUserId,
          p_email: email,
          p_first_name: firstName,
          p_last_name: lastName,
          p_phone: body.phone ?? null,
          p_address: body.address ?? null,
          p_city: body.city ?? null,
          p_postal_code: body.postal_code ?? null,
          p_legal_name: body.legal_name ?? null,
          p_tax_id: body.tax_id ?? null,
          p_notes: body.notes ?? null,
        });

      if (ownerError) {
        console.error(
          "Error creando profile/owner:",
          ownerError,
        );

        // Si falla la creación del propietario,
        // eliminar también el usuario Auth creado.
        await ctx.supabaseAdmin.auth.admin.deleteUser(newUserId);

        return Response.json(
          { error: ownerError.message },
          { status: 400 },
        );
      }

      return Response.json(
        {
          success: true,
          owner_id: ownerId,
          user_id: newUserId,
          email,
          message: "Invitación enviada correctamente.",
        },
        { status: 201 },
      );
    } catch (error) {
      console.error("Error interno:", error);

      return Response.json(
        { error: "Error interno al crear el propietario." },
        { status: 500 },
      );
    }
  }),
};
