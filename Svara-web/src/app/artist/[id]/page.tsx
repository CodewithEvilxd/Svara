import ArtistDetailView from "@/components/ArtistDetailView";
import { SaavnAPI } from "@/services/api";

export default async function ArtistPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const artist = await SaavnAPI.fetchArtistDetailsById(id, 0, 20, 12);

  if (!artist) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center text-gray-400">
        <div className="text-center">
          <h2 className="mb-2 text-2xl font-bold">Artist not found</h2>
          <p>We could not load this artist page right now.</p>
        </div>
      </div>
    );
  }

  return <ArtistDetailView artist={artist} />;
}
