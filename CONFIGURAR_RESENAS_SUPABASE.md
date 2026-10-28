

## Actualización para mostrar el ID verificado en las reseñas
En Supabase abrí **SQL Editor**, ejecutá: `alter table public.resenas add column if not exists player_id text;`. La página guarda el nombre devuelto por el verificador y el ID verificado junto a cada reseña. Los registros anteriores seguirán sin ID porque no se puede reconstruir retroactivamente.
