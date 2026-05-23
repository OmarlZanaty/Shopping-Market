export default function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center h-64">
      <div className="animate-spin w-10 h-10 border-4 border-[#2E5E99] border-t-transparent rounded-full" />
    </div>
  );
}
