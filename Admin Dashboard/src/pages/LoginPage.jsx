import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../stores/authStore';
import toast from 'react-hot-toast';

export default function LoginPage() {
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const { login } = useAuthStore();
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    try {
      await login(phone, password);
      navigate('/dashboard');
      toast.success('Welcome back!');
    } catch (err) {
      toast.error(err.response?.data?.detail || err.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0D2440] to-[#1a3a6e] flex items-center justify-center p-4">
      <div className="bg-white rounded-3xl p-8 w-full max-w-sm shadow-2xl">
        <div className="text-center mb-8">
          <div className="w-16 h-16 bg-[#2E5E99] rounded-2xl flex items-center justify-center text-3xl mx-auto mb-4 shadow-lg">🛒</div>
          <h1 className="text-2xl font-bold text-[#0D2440] font-serif">Market Fresh</h1>
          <p className="text-gray-500 text-sm mt-1">Admin Dashboard</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">Phone Number</label>
            <input value={phone} onChange={e => setPhone(e.target.value)} type="text"
              placeholder="01000000000" required
              className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm transition-colors"
            />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600 uppercase tracking-wider block mb-1.5">Password</label>
            <input value={password} onChange={e => setPassword(e.target.value)} type="password"
              placeholder="••••••" required
              className="w-full border-2 border-gray-100 focus:border-[#2E5E99] rounded-xl px-4 py-3 outline-none text-sm transition-colors"
            />
          </div>
          <button type="submit" disabled={loading}
            className="w-full bg-[#0D2440] hover:bg-[#2E5E99] text-white py-3.5 rounded-xl font-bold text-sm transition-colors disabled:opacity-60 mt-2">
            {loading ? '...' : 'Login to Admin Panel'}
          </button>
        </form>
        <p className="text-center text-xs text-gray-400 mt-6">Market Fresh Admin v1.0</p>
      </div>
    </div>
  );
}
