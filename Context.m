classdef Context < handle
% Context
%
%   A program written for the zmq library should
%   instantiate one context and use it to make 
%   all the sockets it needs.

    properties (SetAccess = private, GetAccess = private)
        ptr
    end
    methods
        function obj = Context()
            zmq.Context.load_zmq();
            obj.ptr = calllib('libzmq', 'zmq_ctx_new');
        end

        function delete(obj)
            calllib('libzmq', 'zmq_ctx_destroy', obj.ptr);
        end

        function sock = socket(obj, typ)
            if metaclass(typ) ~= ?zmq.Type
                error('typ should be a zmq.Type instance');
            end
            sock_ptr = calllib('libzmq', 'zmq_socket',...
                obj.ptr, int32(typ));
            if sock_ptr.isNull()
                zmq.internal.ThrowZMQError();
            end
            sock = zmq.Socket(sock_ptr, obj, obj.ptr, typ);
        end
    end
    methods (Static)
        function load_zmq()
        % load_zmq
        %
        %   Load the zmq dll.
        %   This is called automatically when needed.
            if ~libisloaded('libzmq')
                savedir=pwd;
                [mydir, filename, extension] = fileparts(mfilename('fullpath'));
                cd(mydir);
                cd('win64');
                loadlibrary('libzmq', @libzmq_proto);
                cd(savedir);
            end
        end
    end
end