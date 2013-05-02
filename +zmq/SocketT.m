classdef SocketT < handle
    properties (Access = private)
        ptr
        % ctx is a reference to the parent context to prevent
        % it from being garbage collected until all sockets have
        % been closed properly.
        ctx
        ctx_ptr
        socket_type
        msg
        msg_ptr
    end

    properties (Access = private, Constant)
        EAGAIN = 11; % errno if a timeout occured or a non-blocking read found nothing.
        SNDMORE = 2;
        DONTWAIT = 1;
    end

    properties
        send_timeout = Inf
        recv_timeout = Inf
    end

    methods (Access=?zmq.Context)
        function obj = SocketT(ptr, ctx, ctx_ptr, socket_type)
            obj.ptr = ptr;
            obj.ctx = ctx;
            obj.ctx_ptr = ctx_ptr;
            obj.socket_type = socket_type;

            % Initialize a zmq_msg_t that we will use
            % to receive messages.
            obj.msg.m_ = 0;
            obj.msg_ptr = libpointer('zmq_msg_t', obj.msg);
            calllib('zmq', 'zmq_msg_init', obj.msg_ptr);
        end
    end
    methods
        function delete(obj)
            calllib('zmq', 'zmq_close', obj.ptr);
            calllib('zmq', 'zmq_msg_close', obj.msg_ptr);
        end

        function bind(obj, endpoint)
            r = calllib('zmq', 'zmq_bind', obj.ptr, endpoint);
            if r == -1
                zmq.internal.throw_zmq_error();
            end
        end

        function unbind(obj, endpoint)
            r = calllib('zmq', 'zmq_unbind', obj.ptr, endpoint);
            if r == -1
                zmq.internal.throw_zmq_error();
            end
        end

        function connect(obj, endpoint)
            r = calllib('zmq', 'zmq_connect', obj.ptr, endpoint);
            if r == -1
                zmq.internal.throw_zmq_error();
            end
        end

        function disconnect(obj, endpoint)
            r = calllib('zmq', 'zmq_disconnect', obj.ptr, endpoint);
            if r == -1
                zmq.internal.throw_zmq_error();
            end
        end

        function set_timeout(obj, milliseconds)
            obj.send_timeout = milliseconds;
            obj.recv_timeout = milliseconds;
        end

        function send(obj, msg)
            if iscell(msg)
                if isempty(msg)
                    return
                end
                for m = msg
                    assert(ischar(m{1}));
                end
                head = msg{1};
                tail = msg(2:end);
            else
                assert(ischar(msg));
                head = msg;
                tail = {};
            end
            id = tic();
            while true
                time_left = obj.send_timeout - toc(id)*1000;
                timeout = max(min(time_left, 200), 0);
                obj.set_send_timeout(timeout);
                r = obj.send_raw(head, ~isempty(tail));
                if r == -1
                    err = calllib('zmq', 'zmq_errno');
                    if ~(err == obj.EAGAIN && time_left >= 0)
                        zmq.internal.throw_zmq_error();
                    end
                    drawnow();
                else
                    break;
                end
            end
            for i = 1:length(tail)
                r = obj.send_raw(tail{i}, i ~= length(tail));
                if r == -1
                    zmq.internal.throw_zmq_error();
                end
            end
        end

        function [msg, varargout] = recv(obj, varargin)
            blocking = true;
            multi = false;
            for opt = varargin
                switch opt{1}
                case 'multi'
                    multi = true;
                case 'nowait'
                    blocking = false;
                otherwise
                    error('Unsupported option: %s', opt{1})
                end
            end
            [received, msgs] = obj.recv_base(blocking);
            if multi
                msg = msgs;
            else
                msg = cell2mat(msgs);
            end
            if ~blocking
                varargout{1} = received;
            end
        end

        function ptr = get_raw_ptr(obj)
        % get_raw_ptr
        %   Returns a ptr to the underlying zmq socket.
            ptr = obj.ptr;
        end
    end
    methods (Access=private)

        function r = send_raw(obj, msg, sndmore)
            assert(ischar(msg));
            if sndmore
                flags = obj.SNDMORE;
            else
                flags = 0;
            end
            bytes = uint8(msg);
            bytes_ptr = libpointer('voidPtr', bytes);
            r = calllib('zmq', 'zmq_send', ...
                obj.ptr, bytes_ptr, numel(bytes), flags);
        end

        function set_recv_timeout(obj, milliseconds)
            r = calllib('zmqmat', 'zmqmat_set_recv_timeout', obj.ptr, milliseconds);
            if r == -1
                zmq.internal.throw_zmq_error();
            end
        end

        function set_send_timeout(obj, milliseconds)
            r = calllib('zmqmat', 'zmqmat_set_send_timeout', obj.ptr, milliseconds);
            if r == -1
                zmq.internal.throw_zmq_error();
            end
        end

        function [received, msgs] = recv_base(obj, block)
            msgs = {};
            received = true;
            id = tic();
            while true
                if block
                    time_left = obj.recv_timeout - toc(id)*1000;
                    timeout = max(min(time_left, 200), 0);
                else
                    timeout = 0;
                    time_left = -1;
                end
                obj.set_recv_timeout(timeout);
                r = calllib('zmq', 'zmq_msg_recv', ...
                    obj.msg_ptr, obj.ptr, 0);
                if r == -1
                    err = calllib('zmq', 'zmq_errno');
                    if err == obj.EAGAIN
                        if time_left < 0 
                            if block
                                zmq.internal.throw_zmq_error();
                            end
                            received = false;
                            return
                        end
                        drawnow();
                    else
                        zmq.internal.throw_zmq_error();
                    end
                else
                    break;
                end
            end
            while true
                siz = calllib('zmq', 'zmq_msg_size', obj.msg_ptr);
                if siz ~= 0
                    data = calllib('zmq', 'zmq_msg_data', obj.msg_ptr);
                    setdatatype(data, 'uint8Ptr', 1, siz);
                    msgs{end + 1} = char(data.Value);
                else
                    msgs{end + 1} = char([]);
                end
                if ~calllib('zmq', 'zmq_msg_more', obj.msg_ptr)
                    return
                end
                r = calllib('zmq', 'zmq_msg_recv', ...
                    obj.msg_ptr, obj.ptr, 0);
                if r == -1
                    zmq.internal.throw_zmq_error();
                end
            end
        end
    end
end